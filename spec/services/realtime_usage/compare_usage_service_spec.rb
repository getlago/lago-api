# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::CompareUsageService, clickhouse: true do
  subject(:comparison) { described_class.call(subscription:, timestamp:) }

  include_context "with realtime usage availability"

  # The feature flag is off: the comparison has to serve anyway.
  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at: 2.months.ago) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:timestamp) { Time.current }
  let(:duplicates_by_code) { {billable_metric.code => 0} }
  let(:filtered_charge_ids) { [] }

  let(:bucket_units) { BigDecimal(10) }
  let(:bucket_amount_cents) { 1000 }
  let(:bucket_events_count) { 4 }
  let(:events_units) { BigDecimal(10) }
  let(:events_amount_cents) { 1000 }
  let(:events_events_count) { 4 }

  let(:bucket_usage_result) { usage_result(fee(units: bucket_units, amount_cents: bucket_amount_cents, events_count: bucket_events_count)) }
  let(:events_usage_result) { usage_result(fee(units: events_units, amount_cents: events_amount_cents, events_count: events_events_count)) }

  let(:usage_buckets) do
    Events::Stores::UsageBucketSet.new(
      totals: {[charge.id, ""] => Events::Stores::UsageBucketSet::Totals.new(units: bucket_units, events_count: bucket_events_count)}
    )
  end

  def fee(units:, amount_cents:, events_count:, charge_filter_id: nil, grouped_by: {})
    Fee.new(organization:, charge:, charge_filter_id:, units:, amount_cents:, events_count:, grouped_by:)
  end

  # The recheck window is read straight from the events store, which holds no row here.
  def stub_recent_events(received)
    allow(Clickhouse::EventsEnriched).to receive(:where).and_return(
      instance_double(ActiveRecord::Relation, exists?: received)
    )
  end

  def usage_result(*fees)
    usage = SubscriptionUsage.new
    usage.fees = fees
    result = Invoices::CustomerUsageService::Result.new
    result.usage = usage
    result
  end

  before do
    charge

    allow(Invoices::CustomerUsageService).to receive(:call!) do |use_usage_buckets:, usage_filters:, **|
      filtered_charge_ids << usage_filters.filter_by_charge_id
      use_usage_buckets ? bucket_usage_result : events_usage_result
    end

    allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_return(
      RealtimeUsage::FetchBucketsService::Result.new.tap { it.usage_buckets = usage_buckets }
    )

    allow(RealtimeUsage::CountDuplicateEventsService).to receive(:call!).and_return(
      RealtimeUsage::CountDuplicateEventsService::Result.new.tap do
        it.events_count = 4
        it.duplicates_by_code = duplicates_by_code
        it.duplicates_count = duplicates_by_code.values.sum
      end
    )
  end

  it "computes both usages over the same timestamp, without the charge cache and without taxes" do
    comparison

    expect(Invoices::CustomerUsageService).to have_received(:call!).with(
      hash_including(customer:, subscription:, timestamp:, with_cache: false, apply_taxes: false, use_usage_buckets: true)
    )
    expect(Invoices::CustomerUsageService).to have_received(:call!).with(
      hash_including(customer:, subscription:, timestamp:, with_cache: false, apply_taxes: false, use_usage_buckets: false)
    )
  end

  it "computes both usages over the charges the buckets serve only" do
    comparison

    expect(filtered_charge_ids).to eq([[charge.id], [charge.id]])
  end

  it "reports a match and how many comparable charges the buckets served" do
    expect(comparison.differences).to be_empty
    expect(comparison.eligible_charges_count).to eq(1)
    expect(comparison.served_charges_count).to eq(1)
    expect(comparison.declined_reason).to be_nil
    expect(comparison.rows.map(&:classification)).to eq(["match"])
  end

  it "closes the forced gate once the comparison is over" do
    comparison

    expect(RealtimeUsage.forced_gate?).to be(false)
    expect(RealtimeUsage.enabled?(organization)).to be(false)
  end

  it "reports the duplicate density of the compared window" do
    expect(comparison.duplicate_events_count).to eq(0)
  end

  context "when the bucket usage differs from the events store usage" do
    let(:bucket_units) { BigDecimal(12) }
    let(:bucket_amount_cents) { 1200 }
    let(:bucket_events_count) { 5 }

    before { stub_recent_events(false) }

    it "reports the difference on the leaf, with both values" do
      expect(comparison.differences.size).to eq(1)

      difference = comparison.differences.first
      expect(difference.classification).to eq("mismatch")
      expect(difference.billable_metric_code).to eq(billable_metric.code)
      expect(difference.bucket_units).to eq(BigDecimal(12))
      expect(difference.events_units).to eq(BigDecimal(10))
      expect(difference.units_diff).to eq(BigDecimal(2))
      expect(difference.amount_cents_diff).to eq(200)
    end
  end

  context "when the units differ over an unchanged event count and the window holds duplicates" do
    let(:bucket_units) { BigDecimal(12) }
    let(:bucket_amount_cents) { 1200 }
    let(:duplicates_by_code) { {billable_metric.code => 1} }

    before { stub_recent_events(false) }

    it "reports a re-sent transaction id rather than a mismatch" do
      expect(comparison.differences).to be_empty
      expect(comparison.cutover_risks.map(&:classification)).to eq(["resent_transaction_id"])
    end
  end

  context "when the units differ over an unchanged event count without a duplicate to explain it" do
    let(:bucket_units) { BigDecimal(12) }
    let(:bucket_amount_cents) { 1200 }

    before { stub_recent_events(false) }

    it "reports a mismatch rather than a cutover risk" do
      expect(comparison.cutover_risks).to be_empty
      expect(comparison.differences.map(&:classification)).to eq(["mismatch"])
    end
  end

  context "when the duplicates of the window belong to another metric" do
    let(:bucket_units) { BigDecimal(12) }
    let(:bucket_amount_cents) { 1200 }
    let(:duplicates_by_code) { {"another_code" => 3} }

    before { stub_recent_events(false) }

    it "reports a mismatch rather than a cutover risk" do
      expect(comparison.cutover_risks).to be_empty
      expect(comparison.differences.map(&:classification)).to eq(["mismatch"])
    end
  end

  context "when the charge breaks its usage down by presentation group keys" do
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "5", "presentation_group_keys" => [{"value" => "region"}]})
    end

    it "reports the charge as not served rather than comparing it with itself" do
      expect(comparison.served_charges_count).to eq(0)
      expect(comparison.declined_reason).to eq("no_buckets")
      expect(comparison.rows).to be_empty
    end
  end

  context "when an absent group value is empty on one side and nil on the other" do
    let(:bucket_usage_result) { usage_result(fee(units: bucket_units, amount_cents: bucket_amount_cents, events_count: bucket_events_count, grouped_by: {"region" => ""})) }
    let(:events_usage_result) { usage_result(fee(units: events_units, amount_cents: events_amount_cents, events_count: events_events_count, grouped_by: {"region" => nil})) }

    it "matches the leaves rather than reporting two half-empty ones" do
      expect(comparison.rows.size).to eq(1)
      expect(comparison.differences).to be_empty
    end
  end

  context "when the catch-all leaf of a charge mixing filters with group keys is empty" do
    let(:charge) do
      create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "5", "pricing_group_keys" => ["region"]})
    end
    let(:charge_filter) { create(:charge_filter, charge:) }
    let(:bucket_usage_result) { usage_result(fee(units: BigDecimal(0), amount_cents: 0, events_count: 0)) }
    let(:events_usage_result) { usage_result(fee(units: events_units, amount_cents: events_amount_cents, events_count: events_events_count)) }

    before do
      charge_filter
      stub_recent_events(false)
    end

    it "reports it as a mismatch, the stream writing that bucket like any other" do
      expect(comparison.differences.map(&:classification)).to eq(["mismatch"])
      expect(comparison.differences.first.charge_filter_id).to be_nil
    end
  end

  context "when the subscription received events during the comparison" do
    let(:bucket_units) { BigDecimal(12) }
    let(:bucket_amount_cents) { 1200 }
    let(:bucket_events_count) { 5 }

    before do
      stub_recent_events(true)
      stub_const("#{described_class}::RECHECK_DELAY", 0)
    end

    it "compares once more before reporting the difference" do
      expect(comparison.rechecked).to be(true)
      expect(Invoices::CustomerUsageService).to have_received(:call!).exactly(4).times
    end
  end

  context "when the organization still reads the postgres events store" do
    let(:organization) { create(:organization) }

    it "reports the run as declined without computing any usage" do
      expect(comparison.served_charges_count).to eq(0)
      expect(comparison.declined_reason).to eq("postgres_events_store")
      expect(comparison.rows).to be_empty
      expect(Invoices::CustomerUsageService).not_to have_received(:call!)
    end
  end

  context "when the buckets hold nothing for the window" do
    let(:usage_buckets) { Events::Stores::UsageBucketSet.new }

    it "reports the run as declined" do
      expect(comparison.served_charges_count).to eq(0)
      expect(comparison.declined_reason).to eq("no_buckets")
    end
  end

  context "when the plan has no comparable charge" do
    let(:charge) { create(:standard_charge, plan:, billable_metric:, pay_in_advance: true) }

    it "reports that there was nothing to compare" do
      expect(comparison.eligible_charges_count).to eq(0)
      expect(comparison.rows).to be_empty
      expect(comparison.declined_reason).to eq("no_comparable_charges")
    end
  end
end
