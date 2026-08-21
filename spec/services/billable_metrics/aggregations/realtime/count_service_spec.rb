# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::Realtime::CountService, clickhouse: {clean_before: true}, transaction: false do
  subject(:aggregation_result) { count_service.aggregate }

  let(:count_service) do
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
      }
    )
  end

  let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
  let(:plan) { create(:plan, organization: billable_metric.organization) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization: billable_metric.organization) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:charges_from) { Time.current.beginning_of_month }
  let(:charges_to) { Time.current.end_of_month }
  let(:bucket_time) { Time.current.beginning_of_month }

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
        aggregation_type: "count",
        events_count:,
        units:,
        last_event_at: bucket,
        last_ingested_at: bucket
      }
    ])
  end

  context "with buckets in the charges window" do
    before do
      insert_bucket(bucket: bucket_time + 1.hour, events_count: 40, units: 40)
      insert_bucket(bucket: bucket_time + 2.hours, events_count: 2, units: 2)
    end

    it "serves the aggregation by summing the buckets" do
      expect(aggregation_result.aggregation).to eq(42)
      expect(aggregation_result.count).to eq(42)
      expect(aggregation_result.current_usage_units).to eq(42)
    end

    context "when the buckets sit outside the charges window" do
      let(:charges_from) { Time.current.beginning_of_month - 1.month }
      let(:charges_to) { Time.current.beginning_of_month - 1.second }

      it "falls back to the events store" do
        expect(aggregation_result.aggregation).to eq(0)
      end
    end
  end

  context "without buckets" do
    it "falls back to the events store" do
      expect(aggregation_result.aggregation).to eq(0)
    end
  end

  context "with pricing group keys" do
    let(:count_service) do
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
        filters: {grouped_by: ["region"]}
      )
    end

    context "with grouped buckets" do
      before do
        insert_bucket(bucket: bucket_time + 1.hour, events_count: 4, units: 4, grouped_by: {region: "eu"}.to_json)
        insert_bucket(bucket: bucket_time + 2.hours, events_count: 3, units: 3, grouped_by: {region: "eu"}.to_json)
        insert_bucket(bucket: bucket_time + 1.hour, events_count: 3, units: 3, grouped_by: {region: "us"}.to_json)
      end

      it "serves one aggregation per group by summing that group's buckets" do
        groups = aggregation_result.aggregations.sort_by { |a| a.grouped_by["region"] }

        expect(groups.map(&:grouped_by)).to eq([{"region" => "eu"}, {"region" => "us"}])
        expect(groups.map(&:aggregation)).to eq([7, 3])
        expect(groups.map(&:count)).to eq([7, 3])
      end
    end

    context "without grouped buckets" do
      it "falls back to the events store" do
        expect(aggregation_result.aggregations.first.aggregation).to eq(0)
      end
    end
  end
end
