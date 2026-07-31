# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::BillableMetrics::Update do
  let(:required_permission) { "billable_metrics:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:weighted_sum_billable_metric, organization:) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateBillableMetricInput!) {
        updateBillableMetric(input: $input) {
          id,
          name,
          code,
          aggregationType,
          weightedInterval
          recurring
          organization { id },
          filters { key values }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "billable_metrics:update"

  it "updates a billable metric" do
    result = execute_query(
      query: mutation,
      input: {
        id: billable_metric.id,
        name: "New Metric",
        code: "new_metric",
        description: "New metric description",
        aggregationType: "count_agg",
        recurring: false,
        weightedInterval: "seconds",
        filters: [
          {
            key: "region",
            values: %w[usa europe]
          }
        ]
      }
    )

    result_data = result["data"]["updateBillableMetric"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("New Metric")
    expect(result_data["code"]).to eq("new_metric")
    expect(result_data["organization"]["id"]).to eq(membership.organization_id)
    expect(result_data["aggregationType"]).to eq("count_agg")
    expect(result_data["weightedInterval"]).to eq("seconds")
    expect(result_data["recurring"]).to eq(false)
    expect(result_data["filters"].count).to eq(1)
  end

  context "when removing a value that a charge filter relies on" do
    let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[US Europe]) }
    let(:cloud) { create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp]) }
    let(:charge) { create(:standard_charge, billable_metric:, plan: create(:plan, organization:)) }
    let(:charge_filter) { create(:charge_filter, charge:) }

    let(:input) do
      {
        id: billable_metric.id,
        name: billable_metric.name,
        code: billable_metric.code,
        description: billable_metric.description,
        aggregationType: "count_agg",
        filters: [
          {key: "region", values: %w[Europe]},
          {key: "cloud", values: %w[aws gcp]}
        ]
      }
    end

    before do
      create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: %w[US])
      create(:charge_filter_value, charge_filter:, billable_metric_filter: cloud, values: %w[aws])
    end

    it "returns a validation error naming the impacted plans" do
      result = execute_query(query: mutation, input:)

      error = result["errors"].first
      expect(error["extensions"]["status"]).to eq(422)
      expect(error["extensions"]["details"]["filters"]).to eq(["values_used_by_charge_filters"])
      expect(error["extensions"]["details"]["impactedPlanCodes"]).to eq([charge.plan.code])

      expect(charge_filter.reload).not_to be_discarded
    end

    it "discards the impacted charge filter when opted in" do
      result = execute_query(query: mutation, input: input.merge(discardImpactedChargeFilters: true))

      expect(result["errors"]).to be_nil
      expect(charge_filter.reload).to be_discarded
    end
  end
end
