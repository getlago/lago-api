# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::Aggregations::Realtime::CountService do
  subject(:aggregation_result) { count_service.aggregate }

  let(:count_service) do
    described_class.new(
      event_store_class: Events::Stores::PostgresStore,
      charge:,
      subscription:,
      boundaries: {
        from_datetime: charges_from,
        to_datetime: charges_to,
        charges_from_datetime: charges_from,
        charges_to_datetime: charges_to
      }
    )
  end

  let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
  let(:plan) { create(:plan, organization: billable_metric.organization) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:customer) { create(:customer, organization: billable_metric.organization) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  let(:period_from) { Time.current.beginning_of_month }
  let(:period_to) { Time.current.end_of_month }
  let(:charges_from) { period_from }
  let(:charges_to) { period_to }

  context "with a matching projection row" do
    before do
      UsageRealtimeProjection.insert_all([
        {
          organization_id: billable_metric.organization_id,
          subscription_id: subscription.id,
          billing_period_id: SecureRandom.uuid,
          charge_id: charge.id,
          charge_filter_id: "",
          grouped_by: "{}",
          plan_id: plan.id,
          code: billable_metric.code,
          aggregation_type: "count",
          period_charges_from: period_from,
          period_charges_to: period_to,
          events_count: 42,
          units: 42
        }
      ])
    end

    it "serves the aggregation from the projection" do
      expect(aggregation_result.aggregation).to eq(42)
      expect(aggregation_result.count).to eq(42)
      expect(aggregation_result.current_usage_units).to eq(42)
    end

    context "when the projection period disagrees with the boundaries" do
      let(:charges_from) { period_from - 1.month }
      let(:charges_to) { period_from - 1.second }

      it "falls back to the events store" do
        expect(aggregation_result.aggregation).to eq(0)
      end
    end
  end

  context "without a projection row" do
    it "falls back to the events store" do
      expect(aggregation_result.aggregation).to eq(0)
    end
  end
end
