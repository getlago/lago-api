# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:recurring_aggregation_snapshots:compare_usage" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["recipes:recurring_aggregation_snapshots:compare_usage"] }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:, customer: create(:customer, organization:)) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:csv_path) { Rails.root.join("tmp", "recurring_snapshots_comparison_spec_#{SecureRandom.hex(4)}.csv").to_s }

  let(:comparison) { comparison_result(rows: [row]) }
  let(:row) { build_row(snapshot_units: BigDecimal(10)) }
  let(:pay_in_advance_csv_path) { csv_path.sub(/\.csv\z/, "_pay_in_advance.csv") }
  let(:pay_in_advance_comparison) { pay_in_advance_result(rows: [pay_in_advance_row]) }
  let(:pay_in_advance_row) { build_pay_in_advance_row(snapshot_aggregation: BigDecimal(10)) }

  def build_pay_in_advance_row(snapshot_aggregation:)
    aggregation = RecurringAggregationSnapshots::ComparePayInAdvanceService::Aggregation
    values = {count: 4, pay_in_advance_aggregation: BigDecimal(2), full_units_number: nil, current_aggregation: nil,
              max_aggregation: nil, max_aggregation_with_proration: nil, units_applied: nil}

    RecurringAggregationSnapshots::ComparePayInAdvanceService::Row.new(
      event_transaction_id: "tr_1",
      event_timestamp: Time.zone.parse("2022-05-10"),
      charge_id: charge.id,
      billable_metric_code: billable_metric.code,
      charge_filter_id: nil,
      grouped_by: {},
      snapshot_read: true,
      snapshot: aggregation.new(aggregation: snapshot_aggregation, **values),
      full_scan: aggregation.new(aggregation: BigDecimal(10), **values)
    )
  end

  def pay_in_advance_result(rows:)
    RecurringAggregationSnapshots::ComparePayInAdvanceService::Result.new.tap do
      it.rows = rows
      it.differences = rows.select(&:different?)
      it.compared_charges_count = 1
      it.compared_events_count = rows.size
      it.rechecked = false
    end
  end

  def build_row(snapshot_units:)
    totals = RecurringAggregationSnapshots::CompareUsageService::Totals
    RecurringAggregationSnapshots::CompareUsageService::Row.new(
      charge_id: charge.id,
      billable_metric_code: billable_metric.code,
      charge_filter_id: nil,
      grouped_by: {},
      snapshot_read: true,
      snapshot: totals.new(units: snapshot_units, total_aggregated_units: snapshot_units, amount_cents: 1000, events_count: 4),
      full_scan: totals.new(units: BigDecimal(10), total_aggregated_units: BigDecimal(10), amount_cents: 1000, events_count: 4)
    )
  end

  def comparison_result(rows:, snapshot_charges_count: 1)
    RecurringAggregationSnapshots::CompareUsageService::Result.new.tap do
      it.rows = rows
      it.differences = rows.select(&:different?)
      it.compared_charges_count = 1
      it.snapshot_charges_count = snapshot_charges_count
      it.rechecked = false
    end
  end

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  before do
    Rake.application.rake_require("tasks/recipes/recurring_aggregation_snapshots")
    Rake::Task.define_task(:environment)
    task.reenable

    allow(RecurringAggregationSnapshots::CompareUsageService).to receive(:call).and_return(comparison)
    allow(RecurringAggregationSnapshots::ComparePayInAdvanceService).to receive(:call).and_return(pay_in_advance_comparison)
  end

  after { FileUtils.rm_f([csv_path, pay_in_advance_csv_path]) }

  it "lists the aggregation fields the pay in advance comparison compares" do
    expect(RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_AGGREGATION_FIELDS)
      .to eq(RecurringAggregationSnapshots::ComparePayInAdvanceService::Aggregation.members)
  end

  context "with listed subscriptions" do
    before { stub_stdin(organization.id, "y", subscription.id, csv_path) }

    it "compares the given subscription and writes one CSV row per leaf" do
      expect { task.invoke }.to output(/No mismatch over the charges and events read from a snapshot/).to_stdout

      expect(RecurringAggregationSnapshots::CompareUsageService).to have_received(:call).with(subscription:)

      csv = CSV.read(csv_path)
      expect(csv.first).to eq(RECURRING_SNAPSHOTS_CSV_HEADERS)
      expect(csv.second).to eq(
        [
          subscription.id,
          subscription.external_id,
          charge.id,
          billable_metric.code,
          nil,
          "{}",
          "true",
          "10.0",
          "10.0",
          "10.0",
          "10.0",
          "1000",
          "1000",
          "4",
          "4"
        ]
      )

      pay_in_advance_csv = CSV.read(pay_in_advance_csv_path)
      expect(pay_in_advance_csv.first).to eq(RECURRING_SNAPSHOTS_PAY_IN_ADVANCE_CSV_HEADERS)
      expect(pay_in_advance_csv.second).to eq(
        [
          subscription.id,
          subscription.external_id,
          "tr_1",
          "2022-05-10T00:00:00.000Z",
          charge.id,
          billable_metric.code,
          nil,
          "{}",
          "true",
          "10.0", "10.0",
          "4", "4",
          "2.0", "2.0",
          nil, nil,
          nil, nil,
          nil, nil,
          nil, nil,
          nil, nil
        ]
      )
    end

    context "when a pay in advance event mismatches" do
      let(:pay_in_advance_row) { build_pay_in_advance_row(snapshot_aggregation: BigDecimal(12)) }

      it "reports the mismatch" do
        expect { task.invoke }.to output(/1 mismatching event bucket\(s\)/).to_stdout
      end
    end

    context "when a leaf mismatches" do
      let(:row) { build_row(snapshot_units: BigDecimal(12)) }

      it "reports the mismatch" do
        expect { task.invoke }.to output(/Mismatches detected, investigate before enabling the organization/).to_stdout
      end
    end

    context "when no subscription read a snapshot" do
      let(:comparison) { comparison_result(rows: [], snapshot_charges_count: 0) }
      let(:pay_in_advance_comparison) { pay_in_advance_result(rows: []) }

      it "says the run proves nothing about parity" do
        expect { task.invoke }.to output(/this run says nothing about parity/).to_stdout
      end
    end
  end

  context "when every comparison fails" do
    before do
      allow(RecurringAggregationSnapshots::CompareUsageService).to receive(:call)
        .and_return(BaseService::Result.new.service_failure!(code: "boom", message: "boom"))
      stub_stdin(organization.id, "y", subscription.id, csv_path)
    end

    it "says nothing could be compared" do
      expect { task.invoke }.to output(/No subscription could be compared/).to_stdout
    end
  end

  context "when only the pay in advance comparison fails" do
    let(:pay_in_advance_comparison) { BaseService::Result.new.service_failure!(code: "boom", message: "boom") }

    before { stub_stdin(organization.id, "y", subscription.id, csv_path) }

    it "keeps the current usage rows" do
      expect { task.invoke }.to output(/pay in advance: FAILED/).to_stdout
      expect(CSV.read(csv_path).size).to eq(2)
    end
  end

  context "with an unknown listed subscription" do
    before { stub_stdin(organization.id, "y", "#{subscription.id} #{SecureRandom.uuid}", csv_path) }

    it "names the skipped id" do
      expect { task.invoke }.to output(/Not found in the organization, skipped/).to_stdout
      expect(RecurringAggregationSnapshots::CompareUsageService).to have_received(:call).once
    end
  end

  context "with an invalid sample size" do
    before { stub_stdin(organization.id, "y", "", "abc") }

    it "aborts" do
      expect { task.invoke }.to raise_error(SystemExit).and output(/Organization has/).to_stdout
    end
  end

  context "without listed subscriptions" do
    let(:other_subscription) { create(:subscription, organization:, customer: subscription.customer) }

    before do
      other_subscription
      create(:subscription, customer: create(:customer))
      stub_stdin(organization.id, "y", "", "1", csv_path)
    end

    it "samples the active subscriptions of the organization" do
      expect { task.invoke }.to output(/Organization has 2 active subscription\(s\)/).to_stdout

      expect(RecurringAggregationSnapshots::CompareUsageService).to have_received(:call).once
      expect(RecurringAggregationSnapshots::CompareUsageService).to have_received(:call)
        .with(subscription: satisfy { [subscription, other_subscription].include?(it) })
    end
  end
end
