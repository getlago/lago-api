# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::Realtime::SumService, clickhouse: {clean_before: true}, transaction: false do
  subject(:aggregation_result) { sum_service.aggregate }

  let(:sum_service) do
    described_class.new(
      event_store_class: Events::Stores::PostgresStore,
      charge:,
      subscription:,
      # Same hash shape as Fees::ChargeService#aggregator: :from_datetime is
      # the charges window start and there is no :charges_from_datetime key.
      boundaries: {
        from_datetime: charges_from,
        to_datetime: charges_to,
        charges_duration: nil,
        max_timestamp: nil
      },
      prefetched_buckets:
    )
  end

  let(:billable_metric) { create(:sum_billable_metric) }
  let(:plan) { create(:plan, organization: billable_metric.organization) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization: billable_metric.organization) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:charges_from) { Time.current.beginning_of_month }
  let(:charges_to) { Time.current.end_of_month }
  let(:bucket_time) { Time.current.beginning_of_month }
  let(:prefetched_buckets) { nil }

  def insert_bucket(bucket:, events_count:, units:, grouped_by: "{}")
    Clickhouse::UsageBucket.insert_all([
      {
        bucket:,
        organization_id: billable_metric.organization_id,
        subscription_id: subscription.id,
        customer_id: customer.id,
        plan_id: plan.id,
        code: billable_metric.code,
        charge_id: charge.id,
        charge_filter_id: "",
        grouped_by:,
        aggregation_type: "sum",
        events_count:,
        units:,
        last_event_at: bucket,
        last_ingested_at: bucket
      }
    ])
  end

  context "with buckets in the charges window" do
    before do
      insert_bucket(bucket: bucket_time + 1.hour, events_count: 3, units: 40)
      insert_bucket(bucket: bucket_time + 2.hours, events_count: 1, units: 2)
    end

    # sum aggregates units; count carries the event count, which is a different number here (the
    # count aggregation is the one where they coincide).
    it "serves the aggregation by summing the buckets' units" do
      expect(aggregation_result.aggregation).to eq(42)
      expect(aggregation_result.count).to eq(4)
      expect(aggregation_result.pay_in_advance_aggregation).to eq(0)
    end

    context "when the buckets sit outside the charges window" do
      let(:charges_from) { Time.current.beginning_of_month - 1.month }
      let(:charges_to) { Time.current.beginning_of_month - 1.second }

      it "falls back to the events store" do
        expect(aggregation_result.aggregation).to eq(0)
      end
    end
  end

  # units is Decimal(38, 26) in ClickHouse. A float round-trip anywhere on this path would show up
  # as a rounding error on a customer's bill.
  context "with fractional units" do
    before do
      insert_bucket(bucket: bucket_time + 1.hour, events_count: 1, units: BigDecimal("0.00000000000000000000000001"))
      insert_bucket(bucket: bucket_time + 2.hours, events_count: 1, units: BigDecimal("0.00000000000000000000000002"))
    end

    it "keeps the full scale of the decimal" do
      expect(aggregation_result.aggregation).to eq(BigDecimal("0.00000000000000000000000003"))
      expect(aggregation_result.aggregation).to be_a(BigDecimal)
    end
  end

  context "without buckets" do
    it "falls back to the events store" do
      expect(aggregation_result.aggregation).to eq(0)
    end
  end

  context "with pricing group keys" do
    let(:sum_service) do
      described_class.new(
        event_store_class: Events::Stores::PostgresStore,
        charge:,
        subscription:,
        boundaries: {
          from_datetime: charges_from,
          to_datetime: charges_to,
          charges_duration: nil,
          max_timestamp: nil
        },
        filters: {grouped_by: ["region"]},
        prefetched_buckets:
      )
    end

    context "with grouped buckets" do
      before do
        insert_bucket(bucket: bucket_time + 1.hour, events_count: 2, units: 4, grouped_by: {region: "eu"}.to_json)
        insert_bucket(bucket: bucket_time + 2.hours, events_count: 1, units: 3, grouped_by: {region: "eu"}.to_json)
        insert_bucket(bucket: bucket_time + 1.hour, events_count: 1, units: 3, grouped_by: {region: "us"}.to_json)
      end

      it "serves one aggregation per group by summing that group's units" do
        groups = aggregation_result.aggregations.sort_by { |a| a.grouped_by["region"] }

        expect(groups.map(&:grouped_by)).to eq([{"region" => "eu"}, {"region" => "us"}])
        expect(groups.map(&:aggregation)).to eq([7, 3])
        expect(groups.map(&:count)).to eq([3, 1])
      end
    end

    context "without grouped buckets" do
      it "falls back to the events store" do
        expect(aggregation_result.aggregations.first.aggregation).to eq(0)
      end
    end
  end

  # Events::BillingPeriodFilterService reads the whole plan's window in one query and hands the
  # rows down, so the aggregator must not re-read ClickHouse per charge filter.
  describe "prefetched buckets" do
    context "with prefetched totals" do
      let(:prefetched_buckets) { {"{}" => [2, 4, BigDecimal(42)]} }

      it "serves the aggregation without querying ClickHouse" do
        expect(Clickhouse::UsageBucket).not_to receive(:final)

        expect(aggregation_result.aggregation).to eq(42)
        expect(aggregation_result.count).to eq(4)
      end

      it "prefers the prefetch over the stored buckets" do
        insert_bucket(bucket: bucket_time + 1.hour, events_count: 1, units: 999)

        expect(aggregation_result.aggregation).to eq(42)
      end
    end

    context "with fractional prefetched units" do
      let(:prefetched_buckets) { {"{}" => [1, 1, BigDecimal("0.00000000000000000000000003")]} }

      it "keeps the full scale of the decimal" do
        expect(aggregation_result.aggregation).to eq(BigDecimal("0.00000000000000000000000003"))
      end
    end

    # Prefetched-and-empty: the batch read found no buckets, which has to reach the aggregator as
    # the same fallback a direct query would have produced, without issuing that query.
    context "with an empty prefetch" do
      let(:prefetched_buckets) { {} }

      it "falls back to the events store without querying ClickHouse" do
        expect(Clickhouse::UsageBucket).not_to receive(:final)

        expect(aggregation_result.aggregation).to eq(0)
      end
    end

    # A zero count is a real bucket row that aggregates to nothing, distinct from no row at all.
    context "with a zero count in the prefetch" do
      let(:prefetched_buckets) { {"{}" => [0, 0, BigDecimal(0)]} }

      it "falls back to the events store" do
        expect(aggregation_result.aggregation).to eq(0)
      end
    end
  end
end
