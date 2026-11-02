# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::RealtimeUsage::DimensionsResolver, clickhouse: {clean_before: true}, transaction: false do
  let(:required_permission) { "analytics:view" }
  let(:query) do
    <<~GQL
      query($billableMetricCode: String!, $page: Int, $limit: Int, $fromDatetime: ISO8601DateTime, $toDatetime: ISO8601DateTime) {
        realtimeUsageDimensions(
          billableMetricCode: $billableMetricCode, page: $page, limit: $limit, fromDatetime: $fromDatetime, toDatetime: $toDatetime
        ) {
          collection { name units points { time units } }
          metadata { currentPage totalCount totalPages }
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
  let(:variables) do
    {billableMetricCode: billable_metric.code, page: 2, limit: 1, fromDatetime: "2026-08-24T09:00:00Z", toDatetime: "2026-08-24T11:00:00Z"}
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

  it "pages through the dimensions of the metric" do
    result = execute_graphql(current_user: membership.user, current_organization: organization, permissions: required_permission, query:, variables:)

    expect(result["data"]["realtimeUsageDimensions"]).to eq(
      "collection" => [
        {"name" => "eu", "units" => 5.0, "points" => [{"time" => "2026-08-24T09:00:00Z", "units" => 0.0}, {"time" => "2026-08-24T10:00:00Z", "units" => 5.0}]}
      ],
      "metadata" => {"currentPage" => 2, "totalCount" => 2, "totalPages" => 2}
    )
  end
end
