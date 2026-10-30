# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RealtimeUsage::BillableMetricResolver, clickhouse: {clean_before: true}, transaction: false do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($billableMetricCode: String!, $dimensionKeys: [String!], $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime) {
        realtimeUsageBillableMetric(
          billableMetricCode: $billableMetricCode, dimensionKeys: $dimensionKeys, fromDatetime: $fromDatetime, toDatetime: $toDatetime
        ) {
          billableMetricCode units
          dimensions { key name units }
        }
      }
    GQL
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:charge) { create(:standard_charge, billable_metric:, plan: subscription.plan) }
  let(:billable_metric_code) { billable_metric.code }
  let(:dimension_keys) { nil }
  let(:variables) do
    {billableMetricCode: billable_metric_code, dimensionKeys: dimension_keys, fromDatetime: "2026-08-24T09:00:00Z", toDatetime: "2026-08-24T11:00:00Z"}
  end

  include_context "with realtime usage availability"

  before do
    %w[eu us].each_with_index do |region, index|
      create(:clickhouse_usage_bucket, subscription:, customer:, organization:, billable_metric:, charge:,
        bucket: Time.zone.parse("2026-08-24 10:15:00"), grouped_by: %({"region":"#{region}"}), units: 5 + index)
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  it "returns the usage of the metric per dimension" do
    result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

    expect(result["data"]["realtimeUsageBillableMetric"]).to eq(
      "billableMetricCode" => billable_metric.code,
      "units" => 11.0,
      "dimensions" => [
        {"key" => %(\u001F{"region":"us"}), "name" => "us", "units" => 6.0},
        {"key" => %(\u001F{"region":"eu"}), "name" => "eu", "units" => 5.0}
      ]
    )
  end

  context "with dimension keys" do
    let(:dimension_keys) { [%(\u001F{"region":"eu"})] }

    it "only returns them" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect(result["data"]["realtimeUsageBillableMetric"]["dimensions"].map { |dimension| dimension["name"] }).to eq(["eu"])
    end
  end

  context "with an unknown metric" do
    let(:billable_metric_code) { "unknown" }

    it "returns a not found error" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "with a metric the buckets do not serve" do
    let(:billable_metric_code) { create(:billable_metric, organization:, aggregation_type: "unique_count_agg", field_name: "value").code }

    it "returns a validation error" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect_unprocessable_entity(result)
    end
  end
end
