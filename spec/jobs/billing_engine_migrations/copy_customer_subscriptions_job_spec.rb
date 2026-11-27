# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyCustomerSubscriptionsJob do
  subject(:copy_job) { described_class }

  let(:migration) { create(:billing_engine_migration) }
  let(:customer) { create(:customer, organization: migration.organization) }
  let(:older_subscription) { create(:subscription, customer:, started_at: 2.months.ago) }
  let(:newer_subscription) { create(:subscription, customer:, started_at: 1.month.ago) }
  let(:other_organization_subscription) { create(:subscription) }
  let(:subscription_ids) { [newer_subscription.id, older_subscription.id, other_organization_subscription.id] }

  before { allow(BillingEngineMigrations::CopySubscriptionService).to receive(:call!) }

  it_behaves_like "a unique job" do
    let(:job_args) { [migration, subscription_ids] }

    before { job_args }
  end

  it "copies the subscriptions of the migrated organization one by one, oldest first" do
    copy_job.perform_now(migration, subscription_ids)

    expect(BillingEngineMigrations::CopySubscriptionService)
      .to have_received(:call!).with(migration:, subscription: older_subscription).ordered
    expect(BillingEngineMigrations::CopySubscriptionService)
      .to have_received(:call!).with(migration:, subscription: newer_subscription).ordered
    expect(BillingEngineMigrations::CopySubscriptionService).to have_received(:call!).twice
  end

  context "when the billing schedule of the shadow customer is locked" do
    before do
      allow(BillingEngineMigrations::CopySubscriptionService).to receive(:call!).and_raise(
        BaseService::LockAcquisitionFailure.new(BaseService::Result.new, code: "lock_acquisition_failed", error_message: "locked")
      )
    end

    it "retries the job" do
      expect { copy_job.perform_now(migration, subscription_ids) }
        .to have_enqueued_job(described_class).with(migration, subscription_ids)
    end
  end

  context "when a copy fails" do
    let(:failure) do
      BaseService::Result.new.single_validation_failure!(field: :plan_code, error_code: "value_is_invalid").error
    end

    before do
      allow(BillingEngineMigrations::CopySubscriptionService)
        .to receive(:call!).with(migration:, subscription: older_subscription).and_raise(failure)
    end

    it "raises without retrying or copying the next subscriptions" do
      expect { copy_job.perform_now(migration, subscription_ids) }
        .to raise_error(BaseService::ValidationFailure)
        .and not_have_enqueued_job(described_class)

      expect(BillingEngineMigrations::CopySubscriptionService)
        .not_to have_received(:call!).with(migration:, subscription: newer_subscription)
    end
  end
end
