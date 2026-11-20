# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "billing_engine_migrations:backfill_subscriptions" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["billing_engine_migrations:backfill_subscriptions"] }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:plan) { create(:plan, organization:) }
  let_it_be(:other_plan) { create(:plan, organization:) }
  let_it_be(:customer) { create(:customer, organization:) }

  let(:status) { "shadowing" }
  let(:migration) do
    create(:billing_engine_migration, organization:, status:, plan_mapping: {plan.code => "catalog_plan"})
  end

  let(:override_subscription) do
    create(:subscription, organization:, customer:, plan: create(:plan, organization:, code: plan.code, parent: plan))
  end

  let(:eligible_subscriptions) { create_list(:subscription, 2, organization:, customer:, plan:) }

  before do
    Rake.application.rake_require("tasks/billing_engine_migrations")
    Rake::Task.define_task(:environment)
    task.reenable

    migration
    eligible_subscriptions
    create(:subscription, organization:, customer:, plan: other_plan)
    create(:subscription, :terminated, organization:, customer:, plan:)
    override_subscription
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
    it "lists the subscriptions to copy and to skip and enqueues nothing" do
      expect { task.invoke(organization.id) }.to output(
        a_string_including(
          *eligible_subscriptions.map { |subscription| "would copy subscription #{subscription.external_id}" },
          "would skip subscription #{override_subscription.external_id} (plan_override_not_supported)",
          "Would enqueue 2 subscription(s), skipped 1"
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

    it "enqueues one job per eligible subscription" do
      expect { task.invoke(organization.id) }.to output(/Enqueued 2 subscription\(s\), skipped 1/).to_stdout

      eligible_subscriptions.each do |subscription|
        expect(BillingEngineMigrations::CopySubscriptionJob).to have_been_enqueued.with(migration, subscription)
      end
      expect(BillingEngineMigrations::CopySubscriptionJob).to have_been_enqueued.exactly(2).times
    end
  end
end
