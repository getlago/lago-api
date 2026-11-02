# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:recurring_aggregation_snapshots:backfill" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["recipes:recurring_aggregation_snapshots:backfill"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:to_datetime) { Time.zone.parse("2026-09-30T23:59:59") }

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  before do
    Rake.application.rake_require("tasks/recipes/recurring_aggregation_snapshots_backfill")
    Rake::Task.define_task(:environment)
    task.reenable

    charge
    create(
      :invoice_subscription,
      subscription:,
      invoice: create(:invoice, organization:, customer:),
      invoicing_reason: :subscription_periodic,
      timestamp: to_datetime + 1.second,
      from_datetime: Time.zone.parse("2026-09-01"),
      to_datetime:,
      charges_from_datetime: Time.zone.parse("2026-09-01"),
      charges_to_datetime: to_datetime
    )
  end

  context "with listed subscriptions" do
    let(:terminated_subscription) { create(:subscription, :terminated, organization:, customer:) }

    before { stub_stdin(organization.id, "y", "#{subscription.id},#{terminated_subscription.id}") }

    it "writes the snapshots of each subscription and prints a summary" do
      expect { task.invoke }.to output(
        a_string_including(
          "Warning: recurring_aggregation_snapshots is off",
          "Subscription #{subscription.id} (#{subscription.external_id}): period ending 2026-09-30T23:59:59Z, " \
          "1 charge(s) written, 0 skipped, 0 failed",
          "Subscription #{terminated_subscription.id} (#{terminated_subscription.external_id}): not backfilled, subscription_not_active",
          "Charges written: 1, skipped: 0, failed: 0, subscriptions not backfilled: 1"
        )
      ).to_stdout

      expect(RecurringAggregationSnapshot.where(subscription:).sole).to have_attributes(charge_id: charge.id, units: 0)
    end
  end

  context "with a subscription without invoiced period" do
    let(:new_subscription) { create(:subscription, organization:, customer:) }

    before { stub_stdin(organization.id, "y", new_subscription.id) }

    it "reports it" do
      expect { task.invoke }.to output(/Subscription #{new_subscription.id} \(#{new_subscription.external_id}\): no invoiced period/).to_stdout
    end
  end

  context "with the snapshot writes on" do
    let(:organization) { create(:organization, feature_flags: ["recurring_aggregation_snapshots"]) }

    before { stub_stdin(organization.id, "y", subscription.id) }

    it "does not warn" do
      expect { task.invoke }.not_to output(/Warning/).to_stdout
    end
  end
end
