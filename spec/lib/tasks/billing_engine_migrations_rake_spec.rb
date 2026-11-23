# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:backfill_subscriptions" do # rubocop:disable RSpec/DescribeClass
  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let_it_be(:plan) { create(:plan, organization:) }
  let_it_be(:other_plan) { create(:plan, organization:) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: customer.external_id) }

  let(:task) { Rake::Task["billing_engine_migrations:backfill_subscriptions"] }
  let(:status) { "shadowing" }
  let(:migration) do
    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      status:,
      plan_mapping: {plan.code => "catalog_plan"}
    )
  end

  let(:eligible_subscriptions) { create_list(:subscription, 2, organization:, customer:, plan:) }

  let(:override_subscription) do
    create(:subscription, organization:, customer:, plan: create(:plan, organization:, code: plan.code, parent: plan))
  end

  let(:ended_subscription) { create(:subscription, organization:, customer:, plan:, ending_at: 1.day.ago) }

  let(:copied_subscription) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create(:contract, organization: shadow_organization, customer: shadow_customer, external_id: subscription.external_id)
    end
  end

  let(:recopiable_subscription) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create(:contract, :terminated, organization: shadow_organization, customer: shadow_customer, external_id: subscription.external_id)
    end
  end

  let(:subscription_with_contract_elsewhere) do
    create(:subscription, organization:, customer:, plan:).tap do |subscription|
      create(:contract, external_id: subscription.external_id)
    end
  end

  let(:subscriptions_to_copy) do
    eligible_subscriptions + [recopiable_subscription, subscription_with_contract_elsewhere]
  end

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable

    migration
    subscriptions_to_copy
    override_subscription
    ended_subscription
    copied_subscription
    create(:subscription, organization:, customer:, plan: other_plan)
    create(:subscription, :terminated, organization:, customer:, plan:)
  end

  context "without an organization_id argument" do
    it "aborts with a usage message" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Missing organization_id argument/).to_stderr
    end
  end

  context "when the organization has no migration" do
    it "aborts" do
      expect { task.invoke(create(:organization).id) }
        .to raise_error(SystemExit).and output(/No billing engine migration/).to_stderr
    end
  end

  context "when the migration is not shadowing" do
    let(:status) { "paused" }

    it "aborts without enqueuing anything" do
      expect { task.invoke(organization.id) }.to raise_error(SystemExit).and output(/not shadowing/).to_stderr

      expect(BillingEngineMigrations::CopySubscriptionJob).not_to have_been_enqueued
    end
  end

  context "when DRY_RUN is enabled (default)" do
    it "lists the subscriptions to copy and to skip with the reason, and enqueues nothing" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          *subscriptions_to_copy.map { |subscription| "[DRY RUN] would copy subscription #{subscription.external_id}" },
          "[DRY RUN] would skip subscription #{override_subscription.external_id} (plan_override_not_supported)",
          "[DRY RUN] would skip subscription #{ended_subscription.external_id} (already_ended)",
          "[DRY RUN] would skip subscription #{copied_subscription.external_id} (already_copied)",
          "Would enqueue 4 subscription(s), skipped 3 " \
          "(already_copied: 1, already_ended: 1, plan_override_not_supported: 1) [DRY RUN]"
        )
      ).to_stdout

      expect(BillingEngineMigrations::CopySubscriptionJob).not_to have_been_enqueued
    end
  end

  context "when DRY_RUN is disabled" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "enqueues one job per subscription to copy and lists the skipped ones" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          "[LIVE] skipped subscription #{copied_subscription.external_id} (already_copied)",
          "Enqueued 4 subscription(s), skipped 3"
        )
      ).to_stdout

      subscriptions_to_copy.each do |subscription|
        expect(BillingEngineMigrations::CopySubscriptionJob).to have_been_enqueued.with(migration, subscription)
      end
      expect(BillingEngineMigrations::CopySubscriptionJob).to have_been_enqueued.exactly(4).times
    end
  end
end
