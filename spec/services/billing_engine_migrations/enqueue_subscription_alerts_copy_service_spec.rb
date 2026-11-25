# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::EnqueueSubscriptionAlertsCopyService do
  subject(:enqueue) { described_class.call(subscription:) }

  let(:organization) { create(:organization) }
  let(:mapped_plan) { create(:plan, organization:) }
  let(:plan) { mapped_plan }
  let(:subscription) { create(:subscription, organization:, plan:) }
  let(:migration_status) { "shadowing" }
  let(:migration) do
    create(:billing_engine_migration, organization:, status: migration_status, plan_mapping: {mapped_plan.code => "catalog_plan"})
  end

  let(:v1_alert) { create(:usage_current_amount_alert, organization:, subscription_external_id: subscription.external_id) }

  before do
    migration
    subscription
    v1_alert
    BillingEngineMigrations::Lookup.expire!
  end

  it "enqueues the alert copy of the subscription after the commit" do
    expect { enqueue }
      .to have_enqueued_job_after_commit(BillingEngineMigrations::CopySubscriptionAlertsJob).with(migration.id, subscription)
  end

  it "returns a successful result" do
    expect(enqueue).to be_success
  end

  it "looks the migration up only after the commit" do
    allow(BillingEngineMigrations::Lookup).to receive(:for_source).and_call_original

    ActiveRecord::Base.transaction do
      described_class.call(subscription:)

      expect(BillingEngineMigrations::Lookup).not_to have_received(:for_source)
    end

    expect(BillingEngineMigrations::Lookup).to have_received(:for_source).with(organization.id)
  end

  it "enqueues nothing when the transaction rolls back" do
    expect do
      ActiveRecord::Base.transaction do
        described_class.call(subscription:)
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
  end

  context "when the subscription has no alert and its external id no copy" do
    let(:v1_alert) { nil }

    it "enqueues nothing" do
      expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
    end
  end

  context "when only a copy is left on the external id" do
    let(:v1_alert) { nil }

    before do
      create(:contract_alert, organization: migration.shadow_organization, contract_external_id: subscription.external_id)
    end

    it "enqueues the alert copy so the reconcile removes it" do
      expect { enqueue }
        .to have_enqueued_job_after_commit(BillingEngineMigrations::CopySubscriptionAlertsJob).with(migration.id, subscription)
    end
  end

  context "when the only copy on the external id belongs to another organization" do
    let(:v1_alert) { nil }

    before { create(:contract_alert, contract_external_id: subscription.external_id) }

    it "enqueues nothing" do
      expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
    end
  end

  context "when the plan is not mapped" do
    let(:plan) { create(:plan, organization:) }

    it "enqueues nothing" do
      expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
    end
  end

  context "when the migration is paused" do
    let(:migration_status) { "paused" }

    it "enqueues nothing" do
      expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
    end
  end

  context "when the migration is aborted" do
    let(:migration_status) { "aborted" }

    it "enqueues nothing" do
      expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
    end
  end

  context "when the organization has no migration" do
    let(:migration) { create(:billing_engine_migration, plan_mapping: {mapped_plan.code => "catalog_plan"}) }

    it "enqueues nothing" do
      expect { enqueue }.not_to have_enqueued_job(BillingEngineMigrations::CopySubscriptionAlertsJob)
    end

    it "does not read the plan" do
      BillingEngineMigrations::Lookup.for_source(organization.id)
      fresh_subscription = Subscription.find(subscription.id)

      statements = capture_sql { described_class.call(subscription: fresh_subscription) }

      expect(statements.grep(/billing_engine_migrations|FROM "plans"/)).to be_empty
    end
  end

  context "when the migration is given" do
    subject(:enqueue) { described_class.call(subscription:, migration:) }

    let(:migration_status) { "paused" }
    let(:plan) { create(:plan, organization:) }

    before { allow(BillingEngineMigrations::Lookup).to receive(:for_source).and_call_original }

    it "enqueues the alert copy for that migration without the lookup" do
      expect { enqueue }
        .to have_enqueued_job_after_commit(BillingEngineMigrations::CopySubscriptionAlertsJob).with(migration.id, subscription)

      expect(BillingEngineMigrations::Lookup).not_to have_received(:for_source)
    end
  end

  context "when the lookup cannot load the migrations" do
    before do
      allow(BillingEngineMigrations::Lookup).to receive(:for_source).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports the error without raising" do
      expect { enqueue }.not_to raise_error

      expect(Sentry).to have_received(:capture_exception)
        .with(ActiveRecord::ConnectionNotEstablished, extra: {subscription_id: subscription.id})
    end
  end

  context "when Redis is unreachable" do
    let(:redis_error) { RedisClient::CannotConnectError.new("no connection") }

    before do
      allow(BillingEngineMigrations::Lookup).to receive(:for_source).and_raise(redis_error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports the error without raising" do
      expect { enqueue }.not_to raise_error

      expect(Sentry).to have_received(:capture_exception).with(redis_error, extra: {subscription_id: subscription.id})
    end
  end

  context "when the uniqueness lock cannot reach Redis" do
    let(:lock_error) { Redlock::LockError.new("Too many Redis errors") }

    before do
      allow(ActiveJob::Uniqueness.lock_manager).to receive(:lock).and_raise(lock_error)
      allow(Sentry).to receive(:capture_exception)
    end

    it "reports the error without raising" do
      expect { enqueue }.not_to raise_error

      expect(Sentry).to have_received(:capture_exception).with(lock_error, extra: {subscription_id: subscription.id})
    end
  end

  context "when the error happens inside a transaction" do
    before do
      allow(BillingEngineMigrations::Lookup).to receive(:for_source).and_raise(ActiveRecord::ConnectionNotEstablished)
      allow(Sentry).to receive(:capture_exception)
    end

    it "keeps the committed write" do
      expect do
        ActiveRecord::Base.transaction do
          subscription.update!(name: "Renamed")
          described_class.call(subscription:)
        end
      end.not_to raise_error

      expect(subscription.reload.name).to eq("Renamed")
      expect(Sentry).to have_received(:capture_exception)
    end
  end
end
