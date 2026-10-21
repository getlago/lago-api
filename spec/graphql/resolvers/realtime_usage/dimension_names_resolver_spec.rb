# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RealtimeUsage::DimensionNamesResolver, clickhouse: {clean_before: true}, transaction: false do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($billableMetricCode: String!, $limit: Int, $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime) {
        realtimeUsageDimensionNames(
          billableMetricCode: $billableMetricCode, limit: $limit, fromDatetime: $fromDatetime, toDatetime: $toDatetime
        ) { key name }
      }
    GQL
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
  let(:variables) do
    {billableMetricCode: billable_metric.code, limit: 1, fromDatetime: "2026-08-24T09:00:00Z", toDatetime: "2026-08-24T11:00:00Z"}
  end

  include_context "with realtime usage availability"

  before do
    %w[eu us].each_with_index do |region, index|
      create(:clickhouse_usage_bucket, subscription:, customer:, organization:, billable_metric:,
        bucket: Time.zone.parse("2026-08-24 10:15:00"), grouped_by: %({"region":"#{region}"}), units: 5 + index)
    end
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  it "lists the biggest dimensions of the metric" do
    result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

    expect(result["data"]["realtimeUsageDimensionNames"]).to eq([{"key" => "\u001f{\"region\":\"us\"}", "name" => "us"}])
  end

  context "with an unknown billable metric" do
    let(:variables) { {billableMetricCode: "unknown"} }

    it "returns a not found error" do
      result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
