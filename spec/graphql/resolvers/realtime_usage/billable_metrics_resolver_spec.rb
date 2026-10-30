# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RealtimeUsage::BillableMetricsResolver, clickhouse: {clean_before: true}, transaction: false do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($page: Int, $limit: Int, $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime) {
        realtimeUsageBillableMetrics(page: $page, limit: $limit, fromDatetime: $fromDatetime, toDatetime: $toDatetime) {
          collection {
            billableMetricCode billableMetricName units timeGranularity
            dimensions { name units other }
            points { time units breakdown { units } }
          }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:api_calls) { create(:billable_metric, organization:, name: "API calls", aggregation_type: "count_agg") }
  let(:tokens) { create(:billable_metric, organization:, name: "Tokens", aggregation_type: "sum_agg", field_name: "value") }
  let(:variables) { {page: 1, limit: 1, fromDatetime: "2026-08-24T09:00:00Z", toDatetime: "2026-08-24T11:00:00Z"} }

  include_context "with realtime usage availability"

  before do
    tokens
    create(:billable_metric, organization:, name: "Seats", aggregation_type: "max_agg", field_name: "value")
    create(:billable_metric, organization:, name: "Users", aggregation_type: "unique_count_agg", field_name: "value")
    create(:clickhouse_usage_bucket, subscription:, customer:, organization:, billable_metric: api_calls,
      bucket: Time.zone.parse("2026-08-24 10:15:00"), grouped_by: %({"region":"eu"}), units: 5)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  it "pages through the metrics the buckets serve, by name" do
    result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

    expect(result["data"]["realtimeUsageBillableMetrics"]).to eq(
      "collection" => [
        {
          "billableMetricCode" => api_calls.code,
          "billableMetricName" => "API calls",
          "units" => 5.0,
          "timeGranularity" => "hour",
          "dimensions" => [{"name" => "eu", "units" => 5.0, "other" => false}],
          "points" => [
            {"time" => "2026-08-24T09:00:00Z", "units" => 0.0, "breakdown" => [{"units" => 0.0}]},
            {"time" => "2026-08-24T10:00:00Z", "units" => 5.0, "breakdown" => [{"units" => 5.0}]}
          ]
        }
      ],
      "metadata" => {"currentPage" => 1, "totalCount" => 3}
    )
  end
end
