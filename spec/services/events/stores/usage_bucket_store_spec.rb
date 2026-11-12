# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::UsageBucketStore do
  subject(:store) do
    described_class.new(delegated_store, usage_buckets:, charge_id: charge.id, charge_filter_id:)
  end

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:billing_context) { Billing::Context.from(subscription:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }
  let(:boundaries) { {from_datetime: Time.current.beginning_of_month, to_datetime: Time.current} }
  let(:charge_filter_id) { "" }

  let(:delegated_store) do
    Events::Stores::PostgresStore.new(code: billable_metric.code, billing_context:, boundaries:)
  end

  let(:aggregation_type) { "sum" }
  let(:totals) do
    Events::Stores::UsageBucketSet::Totals.new(
      aggregation_type:, units: BigDecimal("42.5"), events_count: 7, last_event_at: Time.current,
      precise_total_amount_cents: BigDecimal("1234.5")
    )
  end
  let(:grouped_totals) { {} }
  let(:usage_buckets) do
    Events::Stores::UsageBucketSet.new(
      totals: {[charge.id, ""] => totals},
      grouped_totals:
    )
  end

  describe "#precomputed?" do
    it "is true, unlike the store it wraps" do
      expect(store.precomputed?).to be(true)
      expect(delegated_store.precomputed?).to be(false)
    end
  end

  describe "#count" do
    it "answers the units of the buckets" do
      expect(store.count).to eq(
        Events::Stores::BaseStore::AggregationResult.new(value: BigDecimal("42.5"), events_count: 7)
      )
    end
  end

  describe "#sum" do
    it "answers the units of the buckets" do
      expect(store.sum).to eq(
        Events::Stores::BaseStore::AggregationResult.new(value: BigDecimal("42.5"), events_count: 7)
      )
    end

    context "when the buckets hold no row for the charge filter" do
      let(:charge_filter_id) { "unknown" }

      it "answers zero" do
        expect(store.sum.value).to eq(0)
      end
    end
  end

  describe "#sum_precise_total_amount_cents" do
    it "answers the summed precise amount of the buckets" do
      expect(store.sum_precise_total_amount_cents).to eq(BigDecimal("1234.5"))
    end

    context "when the buckets hold no row for the charge filter" do
      let(:charge_filter_id) { "unknown" }

      it "answers zero" do
        expect(store.sum_precise_total_amount_cents).to eq(0)
      end
    end
  end

  describe "#grouped_sum_precise_total_amount_cents" do
    let(:grouped_totals) do
      {[charge.id, ""] => {{"region" => "us"} => totals}}
    end

    it "answers one amount per group of the buckets" do
      expect(store.grouped_sum_precise_total_amount_cents).to eq(
        [{groups: {"region" => "us"}, value: BigDecimal("1234.5")}]
      )
    end
  end

  context "with a recurring charge" do
    subject(:store) do
      described_class.new(
        delegated_store, usage_buckets:, charge_id: charge.id, charge_filter_id:, recurring: true, charges_from_datetime:
      )
    end

    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:charges_from_datetime) { Time.current.beginning_of_month }
    let(:watermark) { Time.current }
    let(:period) do
      RecurringAggregationSnapshots::FetchService::Period.new(
        to_datetime: charges_from_datetime - 1.second, watermark: charges_from_datetime + 1.hour
      )
    end
    let(:late_ingestion) { false }
    let(:usage_buckets) do
      Events::Stores::UsageBucketSet.new(
        totals: {[charge.id, ""] => totals},
        grouped_totals: {[charge.id, ""] => {{"region" => "us"} => totals}}
      )
    end

    before { allow(delegated_store).to receive(:late_ingestion?).and_return(late_ingestion) }

    describe "#recurring_fallback_reason" do
      it { expect(store.recurring_fallback_reason(period)).to be_nil }

      context "without a snapshot period" do
        it { expect(store.recurring_fallback_reason(nil)).to eq("no_period") }
      end

      context "when the snapshot period ends before the previous period" do
        let(:period) do
          RecurringAggregationSnapshots::FetchService::Period.new(
            to_datetime: charges_from_datetime - 1.month - 1.second, watermark: charges_from_datetime - 1.month + 1.hour
          )
        end

        it { expect(store.recurring_fallback_reason(period)).to eq("not_adjacent") }
      end

      context "when the snapshot period ends inside the window" do
        let(:period) do
          RecurringAggregationSnapshots::FetchService::Period.new(
            to_datetime: charges_from_datetime, watermark: charges_from_datetime + 1.hour
          )
        end

        it { expect(store.recurring_fallback_reason(period)).to eq("not_adjacent") }
      end

      context "when the events hold one ingested after the snapshot" do
        let(:late_ingestion) { true }

        it { expect(store.recurring_fallback_reason(period)).to eq("late_ingestion") }
      end

      it "asks the store it wraps once per period" do
        2.times { store.recurring_fallback_reason(period) }

        expect(delegated_store).to have_received(:late_ingestion?).with(period).once
      end
    end

    describe "#recurring_sum" do
      let(:delegated_result) do
        Events::Stores::BaseStore::RecurringAggregationResult.new(
          value: BigDecimal(3), snapshot_value: BigDecimal(3), events_count: 1, snapshot_events_count: 1
        )
      end

      before { allow(delegated_store).to receive(:recurring_sum).and_return(delegated_result) }

      it "answers the units of the window, persisting no snapshot units" do
        expect(store.recurring_sum(watermark:, period:)).to eq(
          Events::Stores::BaseStore::RecurringAggregationResult.new(
            value: BigDecimal("42.5"), snapshot_value: 0, events_count: 7, snapshot_events_count: 0
          )
        )
        expect(delegated_store).not_to have_received(:recurring_sum)
      end

      context "when the buckets hold no row in the window" do
        let(:usage_buckets) { Events::Stores::UsageBucketSet.new }

        it "answers zero" do
          expect(store.recurring_sum(watermark:, period:)).to eq(
            Events::Stores::BaseStore::RecurringAggregationResult.new(
              value: 0, snapshot_value: 0, events_count: 0, snapshot_events_count: 0
            )
          )
        end
      end

      context "when the delta has to come from the events" do
        let(:late_ingestion) { true }

        it "delegates it to the store it wraps" do
          expect(store.recurring_sum(watermark:, period:)).to eq(delegated_result)
          expect(delegated_store).to have_received(:recurring_sum).with(watermark:, period:)
        end
      end
    end

    describe "#grouped_recurring_sum" do
      before { allow(delegated_store).to receive(:grouped_recurring_sum).and_return([]) }

      it "answers one result per group of the window, persisting no snapshot units" do
        expect(store.grouped_recurring_sum(watermark:, period:)).to eq(
          [
            Events::Stores::BaseStore::GroupedRecurringAggregationResult.new(
              groups: {"region" => "us"}, value: BigDecimal("42.5"), snapshot_value: 0, events_count: 7,
              snapshot_events_count: 0
            )
          ]
        )
      end

      context "when the delta has to come from the events" do
        let(:late_ingestion) { true }

        it "delegates it to the store it wraps" do
          expect(store.grouped_recurring_sum(watermark:, period:)).to eq([])
          expect(delegated_store).to have_received(:grouped_recurring_sum).with(watermark:, period:)
        end
      end
    end

    describe "the reads without a snapshot" do
      before do
        allow(delegated_store).to receive_messages(
          sum: :events_sum,
          grouped_sum: :events_grouped_sum,
          sum_precise_total_amount_cents: :events_amount,
          grouped_sum_precise_total_amount_cents: :events_grouped_amount
        )
      end

      it "delegates them, as the window alone is not the recurring total" do
        expect(store.sum).to eq(:events_sum)
        expect(store.grouped_sum).to eq(:events_grouped_sum)
        expect(delegated_store).to have_received(:grouped_sum).with(with_count: true)
        expect(store.sum_precise_total_amount_cents).to eq(:events_amount)
        expect(store.grouped_sum_precise_total_amount_cents).to eq(:events_grouped_amount)
      end
    end
  end

  describe "#max" do
    let(:aggregation_type) { "max" }

    it "answers the units of the buckets" do
      expect(store.max).to eq(
        Events::Stores::BaseStore::AggregationResult.new(value: BigDecimal("42.5"), events_count: 7)
      )
    end
  end

  describe "#last" do
    let(:aggregation_type) { "latest" }

    it "answers the units of the buckets, counting every event of the window alongside" do
      expect(store.last).to eq(
        Events::Stores::BaseStore::AggregationResult.new(value: BigDecimal("42.5"), events_count: 7)
      )
    end
  end

  describe "#grouped_count" do
    let(:grouped_totals) do
      {[charge.id, ""] => {{"region" => "us"} => totals}}
    end

    it "answers one result per group of the buckets" do
      expect(store.grouped_count).to eq(
        [
          Events::Stores::BaseStore::GroupedAggregationResult.new(
            groups: {"region" => "us"}, value: BigDecimal("42.5"), events_count: 7
          )
        ]
      )
    end

    context "when a presentation breakdown is asked for" do
      before { allow(delegated_store).to receive(:grouped_count).and_return([]) }

      it "delegates it, as the buckets cannot answer it" do
        store.grouped_count(["region"])

        expect(delegated_store).to have_received(:grouped_count).with(["region"])
      end
    end
  end

  describe "#grouped_sum" do
    let(:grouped_totals) do
      {[charge.id, ""] => {{"region" => "us"} => totals}}
    end

    it "answers one result per group of the buckets" do
      expect(store.grouped_sum).to eq(
        [
          Events::Stores::BaseStore::GroupedAggregationResult.new(
            groups: {"region" => "us"}, value: BigDecimal("42.5"), events_count: 7
          )
        ]
      )
    end

    context "when a presentation breakdown is asked for" do
      before { allow(delegated_store).to receive(:grouped_sum).and_return([]) }

      it "delegates it, as the buckets cannot answer it" do
        store.grouped_sum(["region"], with_count: false)

        expect(delegated_store).to have_received(:grouped_sum).with(["region"], with_count: false)
      end
    end
  end

  describe "#grouped_max" do
    let(:aggregation_type) { "max" }
    let(:grouped_totals) do
      {[charge.id, ""] => {{"region" => "us"} => totals}}
    end

    it "answers one result per group of the buckets" do
      expect(store.grouped_max).to eq(
        [
          Events::Stores::BaseStore::GroupedAggregationResult.new(
            groups: {"region" => "us"}, value: BigDecimal("42.5"), events_count: 7
          )
        ]
      )
    end

    context "when a presentation breakdown is asked for" do
      before { allow(delegated_store).to receive(:grouped_max).and_return([]) }

      it "delegates it, as the buckets cannot answer it" do
        store.grouped_max(["region"], with_count: false)

        expect(delegated_store).to have_received(:grouped_max).with(["region"], with_count: false)
      end
    end
  end

  describe "#grouped_last" do
    let(:aggregation_type) { "latest" }
    let(:grouped_totals) do
      {[charge.id, ""] => {{"region" => "us"} => totals}}
    end

    it "answers one result per group of the buckets, counting the events of each group" do
      expect(store.grouped_last).to eq(
        [
          Events::Stores::BaseStore::GroupedAggregationResult.new(
            groups: {"region" => "us"}, value: BigDecimal("42.5"), events_count: 7
          )
        ]
      )
    end

    context "when a presentation breakdown is asked for" do
      before { allow(delegated_store).to receive(:grouped_last).and_return([]) }

      it "delegates it, as the buckets cannot answer it" do
        store.grouped_last(["region"], with_count: false)

        expect(delegated_store).to have_received(:grouped_last).with(["region"], with_count: false)
      end
    end
  end

  describe "the aggregations the buckets do not cover" do
    context "when one of them is called" do
      before { allow(delegated_store).to receive(:weighted_sum).and_return(nil) }

      it "delegates it to the store it wraps" do
        store.weighted_sum

        expect(delegated_store).to have_received(:weighted_sum)
      end
    end

    it "forwards the per-charge state the aggregators write" do
      store.aggregation_property = billable_metric.field_name
      store.numeric_property = true

      expect(delegated_store.aggregation_property).to eq(billable_metric.field_name)
      expect(delegated_store.numeric_property).to be(true)
    end

    it "mints a plain store for a sibling window, which no bucket answers for" do
      expect(store.for_window(**boundaries)).to be_a(Events::Stores::PostgresStore)
    end
  end
end
