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

  let(:totals) { Events::Stores::UsageBucketSet::Totals.new(units: BigDecimal("42.5"), events_count: 7) }
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

  describe "the aggregations the buckets do not cover" do
    context "when one of them is called" do
      before { allow(delegated_store).to receive(:max).and_return(nil) }

      it "delegates it to the store it wraps" do
        store.max

        expect(delegated_store).to have_received(:max)
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
