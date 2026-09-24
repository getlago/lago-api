# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "recipes:realtime_usage:compare_usage", :premium do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["recipes:realtime_usage:compare_usage"] }

  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:csv_path) { Rails.root.join("tmp", "realtime_usage_comparison_spec_#{SecureRandom.hex(4)}.csv").to_s }

  let(:comparison) { comparison_result(rows: [row]) }
  let(:row) { build_row(classification: "match") }

  def build_row(classification:, bucket_units: BigDecimal(10), events_units: BigDecimal(10))
    RealtimeUsage::CompareUsageService::Row.new(
      charge_id: charge.id,
      billable_metric_code: billable_metric.code,
      charge_filter_id: nil,
      grouped_by: {},
      classification:,
      bucket_units:,
      events_units:,
      bucket_amount_cents: 1000,
      events_amount_cents: 1000,
      bucket_events_count: 4,
      events_events_count: 4
    )
  end

  def comparison_result(rows:, served_charges_count: 1, declined_reason: nil)
    RealtimeUsage::CompareUsageService::Result.new.tap do
      it.rows = rows
      it.differences = rows.select(&:different?)
      it.cutover_risks = rows.select(&:cutover_risk?)
      it.eligible_charges_count = 1
      it.served_charges_count = served_charges_count
      it.duplicate_events_count = 0
      it.declined_reason = declined_reason
      it.rechecked = false
    end
  end

  def stub_stdin(*responses)
    allow($stdin).to receive(:gets).and_return(*responses.map { "#{it}\n" })
  end

  before do
    Rake.application.rake_require("tasks/recipes/realtime_usage")
    Rake::Task.define_task(:environment)
    task.reenable

    charge
    allow(Events::Stores::StoreFactory).to receive(:supports_clickhouse?).and_return(true)
    allow(RealtimeUsage::CompareUsageService).to receive(:call).and_return(comparison)

    stub_stdin(organization.id, "y", subscription.id, csv_path)
  end

  after { FileUtils.rm_f(csv_path) }

  it "compares the given subscription and writes one CSV row per leaf" do
    expect { task.invoke }.to output(/No mismatch over the charges actually served/).to_stdout

    csv = CSV.read(csv_path)
    expect(csv.first).to eq(REALTIME_USAGE_CSV_HEADERS)
    expect(csv.second).to eq(
      [
        subscription.id,
        subscription.external_id,
        charge.id,
        billable_metric.code,
        nil,
        "{}",
        "match",
        "10.0",
        "10.0",
        "0.0",
        "1000",
        "1000",
        "0",
        "4",
        "4",
        "0"
      ]
    )
  end

  context "when a leaf mismatches" do
    let(:row) { build_row(classification: "mismatch", bucket_units: BigDecimal(12)) }

    it "reports the mismatch" do
      expect { task.invoke }.to output(/Mismatches detected, investigate before enabling the organization/).to_stdout
    end
  end

  context "when the only difference may be explained by a re-sent transaction id" do
    let(:row) { build_row(classification: "resent_transaction_id", bucket_units: BigDecimal(12)) }

    it "reports it rather than calling the run clean" do
      expect { task.invoke }.to output(/Mismatches detected, investigate before enabling the organization/).to_stdout
    end
  end

  context "when nothing was served from the buckets" do
    let(:comparison) { comparison_result(rows: [], served_charges_count: 0, declined_reason: "no_buckets") }

    it "says the run proves nothing about parity" do
      expect { task.invoke }.to output(/this run says nothing about parity/).to_stdout
    end
  end
end
