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
  let(:subscription_ids) { "" }
  let(:dead_set) { [] }

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  def invoice_period(subscription)
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

  def job_entry(subscription, at: nil)
    instance_double(Sidekiq::SortedEntry, display_class: "RecurringAggregationSnapshots::BackfillJob",
      display_args: [subscription.to_global_id.to_s], at:)
  end

  before do
    Rake.application.rake_require("tasks/recipes/recurring_aggregation_snapshots_backfill")
    Rake::Task.define_task(:environment)
    task.reenable

    charge
    invoice_period(subscription)

    stub_stdin(organization.id, "y", subscription_ids, "y")
    allow(Sidekiq::Queue).to receive(:new).and_return([])
    allow(Sidekiq::ScheduledSet).to receive(:new).and_return([])
    allow(Sidekiq::Workers).to receive(:new).and_return([])
    allow(Sidekiq::DeadSet).to receive(:new).and_return(dead_set)
    allow(Kernel).to receive(:sleep)
  end

  it "enqueues a job per subscription of the organization and follows them until they ran" do
    expect { perform_enqueued_jobs { task.invoke } }.to output(
      a_string_including(
        "1 active subscription(s) with a recurring sum charge and an invoiced period.",
        "Enqueued 1 job(s). Stopping this task leaves them running.",
        "  1/1 job(s) ran, 0 pending",
        "Subscriptions backfilled: 1/1, failed: 0, not enqueued: 0, nothing written: 0"
      )
    ).to_stdout

    expect(RecurringAggregationSnapshot.where(subscription:).sole).to have_attributes(charge_id: charge.id, units: 0)
  end

  context "with listed subscriptions" do
    let(:other_subscription) { create(:subscription, organization:, customer:, plan: subscription.plan) }
    let(:terminated_subscription) { create(:subscription, :terminated, organization:, customer:) }
    let(:subscription_ids) { "#{subscription.id},#{terminated_subscription.id}" }

    before { invoice_period(other_subscription) }

    it "backfills those it can only" do
      expect { perform_enqueued_jobs { task.invoke } }.to output(
        a_string_including(
          "Skipped, not found or without a recurring sum charge or an invoiced period:\n#{terminated_subscription.id}\n",
          "Subscriptions backfilled: 1/1, failed: 0, not enqueued: 0, nothing written: 0"
        )
      ).to_stdout

      expect(RecurringAggregationSnapshot.distinct.pluck(:subscription_id)).to eq([subscription.id])
    end
  end

  context "when a job died" do
    let(:dead_set) { [job_entry(subscription, at: 1.minute.from_now), job_entry(create(:subscription, organization:), at: 1.day.ago)] }

    it "lists the subscriptions to rerun" do
      expect { task.invoke }.to output(
        a_string_including(
          "Subscriptions backfilled: 0/1, failed: 1, not enqueued: 0, nothing written: 0",
          "Failed, rerun them by listing them:\n#{subscription.id}\n"
        )
      ).to_stdout
    end
  end

  context "when a job writes nothing" do
    it "lists the subscription apart from the failed ones" do
      expect { task.invoke }.to output(
        a_string_including(
          "Subscriptions backfilled: 0/1, failed: 0, not enqueued: 0, nothing written: 1",
          "Nothing written, no snapshot to store (see Fees::ChargeService):\n#{subscription.id}\n"
        )
      ).to_stdout
    end
  end

  context "with jobs still pending" do
    let(:other_organization_subscription) { create(:subscription) }

    before do
      allow(Sidekiq::Workers).to receive(:new).and_return(
        [["process", "thread", instance_double(Sidekiq::Work, job: job_entry(subscription))]],
        [["process", "thread", instance_double(Sidekiq::Work, job: job_entry(other_organization_subscription))]]
      )
    end

    it "polls until two polls find none of its jobs pending" do
      expect { perform_enqueued_jobs { task.invoke } }.to output(
        a_string_including("  0/1 job(s) ran, 1 pending\n  1/1 job(s) ran, 0 pending\n  1/1 job(s) ran, 0 pending\n\n")
      ).to_stdout
    end
  end

  context "without subscription to backfill" do
    before { RecurringAggregationSnapshots::BackfillService.invoiced_periods.delete_all }

    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/0 active subscription/).to_stdout
    end
  end
end
