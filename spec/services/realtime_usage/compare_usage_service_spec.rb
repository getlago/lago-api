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
      totals: {[charge.id, ""] => Events::Stores::UsageBucketSet::Totals.new(aggregation_type: "sum", units: bucket_units, events_count: bucket_events_count, last_event_at: Time.current)}
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

  context "when the same units were aggregated over another number of events" do
    let(:bucket_events_count) { 5 }

    before { stub_recent_events(false) }

    it "reports the difference, the event count being served with the units" do
      expect(comparison.differences.map(&:classification)).to eq(["mismatch"])
      expect(comparison.differences.first.events_count_diff).to eq(1)
    end
  end

  context "when the units differ over an unchanged event count and the window holds duplicates" do
    let(:bucket_units) { BigDecimal(12) }
    let(:bucket_amount_cents) { 1200 }
    let(:duplicates_by_code) { {billable_metric.code => 1} }

    before { stub_recent_events(false) }

    it "reports the difference and labels it as a possible re-sent transaction id" do
      expect(comparison.differences.map(&:classification)).to eq(["resent_transaction_id"])
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

  context "with a recurring charge" do
    # The flags are off: the comparison opens the recurring charges and reads the snapshots anyway.
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:charges_from_datetime) { timestamp.beginning_of_month }
    let(:watermark) { charges_from_datetime + 1.second }
    let(:snapshot_to_datetime) { charges_from_datetime - 1.second }
    let(:snapshot) { create(:recurring_aggregation_snapshot, subscription:, charge:, to_datetime: snapshot_to_datetime, watermark:) }
    let(:runs) { [] }

    let(:usage_buckets) do
      Events::Stores::UsageBucketSet.new(
        totals: {[charge.id, ""] => Events::Stores::UsageBucketSet::Totals.new(aggregation_type: "sum", units: bucket_units, events_count: bucket_events_count, last_event_at: Time.current)}
      )
    end

    before do
      snapshot

      allow(Invoices::CustomerUsageService).to receive(:call!) do |use_usage_buckets:, usage_filters:, **|
        runs << {
          charge_ids: usage_filters.filter_by_charge_id,
          use_usage_buckets:,
          forced_gate: RealtimeUsage.forced_gate?,
          snapshot_read: RecurringAggregationSnapshots.read_enabled?(organization)
        }
        use_usage_buckets ? bucket_usage_result : events_usage_result
      end
    end

    def create_late_event
      Clickhouse::EventsEnriched.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: snapshot_to_datetime - 1.day,
        properties: {billable_metric.field_name => 3},
        value: "3",
        decimal_value: 3,
        enriched_at: [watermark + 1.minute, Time.current].max
      )
    end

    it "compares it, both runs reading the snapshots and only one the buckets" do
      expect(comparison.eligible_charges_count).to eq(1)
      expect(comparison.served_charges_count).to eq(1)
      expect(comparison.recurring_eligible_charges_count).to eq(1)
      expect(comparison.recurring_served_charges_count).to eq(1)
      expect(comparison.recurring_fallback_reasons).to eq({})
      expect(comparison.rows.map(&:classification)).to eq(["match"])
      expect(runs).to eq(
        [
          {charge_ids: [charge.id], use_usage_buckets: true, forced_gate: true, snapshot_read: true},
          {charge_ids: [charge.id], use_usage_buckets: false, forced_gate: false, snapshot_read: true}
        ]
      )
    end

    it "closes the forced snapshot read once the comparison is over" do
      comparison

      expect(RecurringAggregationSnapshots.read_enabled?(organization)).to be(false)
    end

    context "when an event was ingested into a closed period after the snapshot" do
      before { create_late_event }

      it "reports the charge as falling back rather than comparing the events with themselves" do
        expect(comparison.served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"late_ingestion" => 1})
        expect(comparison.declined_reason).to eq("recurring_fallback")
        expect(comparison.rows).to be_empty
        expect(runs).to be_empty
      end

      context "with a charge served next to it" do
        let(:other_charge) { create(:standard_charge, plan:, billable_metric: create(:sum_billable_metric, organization:)) }

        before { other_charge }

        it "compares the other charge only" do
          expect(comparison.served_charges_count).to eq(1)
          expect(comparison.recurring_fallback_reasons).to eq({"late_ingestion" => 1})
          expect(comparison.declined_reason).to be_nil
          expect(runs.map { it[:charge_ids] }).to eq([[other_charge.id], [other_charge.id]])
        end

        context "when the buckets hold nothing for the other charge" do
          let(:usage_buckets) { Events::Stores::UsageBucketSet.new }

          it "reports the missing buckets of the other charge rather than the recurring fallback" do
            expect(comparison.served_charges_count).to eq(0)
            expect(comparison.recurring_fallback_reasons).to eq({"late_ingestion" => 1})
            expect(comparison.declined_reason).to eq("no_buckets")
          end
        end
      end
    end

    context "when the bucket read was refused" do
      before do
        allow(RealtimeUsage::FetchBucketsService).to receive(:call).and_return(RealtimeUsage::FetchBucketsService::Result.new)
      end

      it "counts the charge as declined, so the reasons add up to the eligible recurring charges" do
        expect(comparison.recurring_eligible_charges_count).to eq(1)
        expect(comparison.recurring_served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"declined" => 1})
        expect(comparison.declined_reason).to eq("no_buckets")
      end
    end

    context "when the organization sends its events to the product events pipeline" do
      let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["product_catalog"]) }

      before { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = "product_events_raw" }

      after { ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = nil }

      it "counts the charge as declined and names the pipeline" do
        expect(comparison.recurring_eligible_charges_count).to eq(1)
        expect(comparison.recurring_served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"declined" => 1})
        expect(comparison.declined_reason).to eq("product_events_pipeline")
        expect(runs).to be_empty
      end
    end

    context "when the snapshot closes an older period than the previous one" do
      let(:snapshot_to_datetime) { charges_from_datetime - 1.month }

      it "reports the charge as falling back" do
        expect(comparison.served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"not_adjacent" => 1})
      end
    end

    context "without a snapshot" do
      let(:snapshot) { nil }

      it "reports the charge as falling back" do
        expect(comparison.served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"no_period" => 1})
      end
    end

    context "when the subscription is the upgrade of another" do
      let(:subscription) do
        create(:subscription, :with_previous_subscription, organization:, customer:, plan:, started_at: 2.months.ago)
      end

      it "reports the refusal of the provider rather than missing buckets" do
        expect(comparison.served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"has_predecessor" => 1})
        expect(comparison.declined_reason).to eq("recurring_fallback")
      end
    end

    context "with a dynamic charge" do
      let(:charge) { create(:dynamic_charge, plan:, billable_metric:) }

      it "reports the refusal of the provider" do
        expect(comparison.served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"dynamic" => 1})
      end
    end

    context "with a charge filter" do
      let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:) }
      let(:charge_filter) do
        create(:charge_filter, charge:, created_at: watermark - 1.day, updated_at: filter_updated_at)
      end
      let(:filter_updated_at) { watermark - 1.day }

      before do
        create(
          :charge_filter_value,
          charge_filter:,
          billable_metric_filter:,
          created_at: watermark - 1.day,
          updated_at: watermark - 1.day
        )
      end

      it "compares it when every bucket starts from the snapshot" do
        expect(comparison.served_charges_count).to eq(1)
        expect(comparison.recurring_fallback_reasons).to eq({})
      end

      context "when only the filter was edited since the snapshot, its bucket being empty" do
        let(:filter_updated_at) { watermark + 1.minute }

        it "reports the charge as falling back once, the default bucket being served" do
          expect(comparison.served_charges_count).to eq(0)
          expect(comparison.recurring_fallback_reasons).to eq({"no_period" => 1})
        end
      end
    end

    context "with pricing group keys" do
      let(:charge) do
        create(:standard_charge, plan:, billable_metric:, properties: {"amount" => "5", "pricing_group_keys" => ["region"]})
      end
      let(:snapshot) do
        create(
          :recurring_aggregation_snapshot,
          subscription:,
          charge:,
          to_datetime: snapshot_to_datetime,
          watermark:,
          grouped_by: {"region" => "eu"}
        )
      end

      it "reads the snapshots grouped on the same keys and compares it" do
        expect(comparison.served_charges_count).to eq(1)
        expect(comparison.recurring_fallback_reasons).to eq({})
      end
    end

    context "when an event lands in the snapshot period between the decision and the bucket run" do
      before do
        allow(Invoices::CustomerUsageService).to receive(:call!).and_wrap_original do |original, use_usage_buckets:, **args|
          create_late_event if use_usage_buckets && runs.empty?
          runs << {use_usage_buckets:}
          original.call(use_usage_buckets:, **args)
        end
      end

      it "decides again, leaving the charge out under late_ingestion rather than failing" do
        expect(comparison).to be_success
        expect(comparison.served_charges_count).to eq(0)
        expect(comparison.recurring_fallback_reasons).to eq({"late_ingestion" => 1})
        expect(runs).to eq([{use_usage_buckets: true}])
      end
    end

    context "when the charge falls back during the bucket run again after deciding once more" do
      before do
        allow(Invoices::CustomerUsageService).to receive(:call!)
          .and_raise(RealtimeUsage::RecurringFallbackError, "charge #{charge.id} fell back to the events")
      end

      it "fails rather than reporting a match the buckets never served" do
        expect(comparison).to be_failure
        expect(comparison.error.code).to eq("recurring_fallback_during_comparison")
        expect(Invoices::CustomerUsageService).to have_received(:call!).twice
      end
    end

    context "when an event lands in the snapshot period between the two runs" do
      let(:bucket_units) { BigDecimal(12) }

      before do
        stub_const("#{described_class}::RECHECK_DELAY", 0)
        allow(Invoices::CustomerUsageService).to receive(:call!) do |use_usage_buckets:, **|
          create_late_event if runs == [true]
          runs << use_usage_buckets
          use_usage_buckets ? bucket_usage_result : events_usage_result
        end
      end

      it "compares once more, as the late event moves the recurring usage, and leaves the charge out" do
        expect(comparison.rechecked).to be(true)
        expect(comparison.differences).to be_empty
        expect(comparison.recurring_fallback_reasons).to eq({"late_ingestion" => 1})
        expect(runs).to eq([true, false])
      end
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

  context "when the bucket read fails during the comparison" do
    let(:bucket_read_failure) do
      result = RealtimeUsage::FetchBucketsService::Result.new
      result.service_failure!(code: "usage_buckets_read_failure", message: "clickhouse is unreachable")
      result.error
    end

    before do
      allow(Invoices::CustomerUsageService).to receive(:call!) do |use_usage_buckets:, **|
        raise bucket_read_failure if use_usage_buckets

        events_usage_result
      end
    end

    it "fails the run rather than comparing the events store with itself" do
      expect(comparison).not_to be_success
      expect(comparison.error.code).to eq("usage_buckets_read_failure")
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
