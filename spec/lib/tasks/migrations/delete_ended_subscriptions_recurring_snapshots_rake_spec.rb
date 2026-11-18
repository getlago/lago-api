# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "migrations:delete_ended_subscriptions_recurring_snapshots" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:delete_ended_subscriptions_recurring_snapshots"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:charge) { create(:standard_charge, organization:, billable_metric: create(:sum_billable_metric, :recurring, organization:)) }
  let(:ended_subscription) { create(:subscription, :terminated, organization:, customer:, plan: charge.plan) }
  let(:upgraded_subscription) { create(:subscription, :terminated, organization:, customer:, plan: charge.plan) }
  let(:active_subscription) { create(:subscription, organization:, customer:, plan: charge.plan) }
  let(:downgrade_canceled_subscription) { create(:subscription, :terminated, organization:, customer:, plan: charge.plan) }

  let(:other_organization) { create(:organization) }
  let(:other_charge) do
    create(:standard_charge, organization: other_organization, billable_metric: create(:sum_billable_metric, :recurring, organization: other_organization))
  end
  let(:other_ended_subscription) do
    create(:subscription, :terminated, organization: other_organization, customer: create(:customer, organization: other_organization), plan: other_charge.plan)
  end

  let!(:upgraded_snapshot) { create(:recurring_aggregation_snapshot, subscription: upgraded_subscription, charge:) }
  let!(:active_snapshot) { create(:recurring_aggregation_snapshot, subscription: active_subscription, charge:) }
  let!(:other_ended_snapshot) { create(:recurring_aggregation_snapshot, subscription: other_ended_subscription, charge: other_charge) }

  before do
    Rake.application.rake_require("tasks/migrations/delete_ended_subscriptions_recurring_snapshots")
    Rake::Task.define_task(:environment)
    task.reenable

    create(:recurring_aggregation_snapshot, subscription: ended_subscription, charge:, to_datetime: 2.months.ago)
    create(:recurring_aggregation_snapshot, subscription: ended_subscription, charge:, to_datetime: 1.month.ago)
    create(:subscription, organization:, customer:, plan: charge.plan, previous_subscription: upgraded_subscription)
    create(:recurring_aggregation_snapshot, subscription: downgrade_canceled_subscription, charge:)
    create(:subscription, :canceled, organization:, customer:, plan: charge.plan, previous_subscription: downgrade_canceled_subscription)
  end

  around do |example|
    ENV["ORGANIZATION_ID"] = organization.id
    example.run
  ensure
    ENV["ORGANIZATION_ID"] = nil
  end

  context "without DRY_RUN" do
    it "lists the snapshots it would delete and deletes nothing" do
      expect { task.invoke }
        .to output(
          a_string_including(
            "[DRY RUN]",
            "subscription=#{ended_subscription.id} organization=#{organization.id} snapshots=2",
            "subscription=#{downgrade_canceled_subscription.id} organization=#{organization.id} snapshots=1",
            "Subscriptions: 2, snapshots to delete: 3."
          )
        ).to_stdout
        .and not_change(RecurringAggregationSnapshot, :count)
    end
  end

  context "when DRY_RUN is false" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    it "deletes the snapshots of the organization's subscriptions terminated without a next subscription" do
      expect { task.invoke }.to output(a_string_including("[LIVE]", "Subscriptions: 2, snapshots deleted: 3.")).to_stdout

      expect(RecurringAggregationSnapshot.all).to match_array([upgraded_snapshot, active_snapshot, other_ended_snapshot])
    end

    context "without ORGANIZATION_ID" do
      before { ENV["ORGANIZATION_ID"] = nil }

      it "deletes them in every organization" do
        expect { task.invoke }.to output(a_string_including("Subscriptions: 3, snapshots deleted: 4.")).to_stdout

        expect(RecurringAggregationSnapshot.all).to match_array([upgraded_snapshot, active_snapshot])
      end
    end
  end
end
