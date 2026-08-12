# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::SelectableBillableMetricsResolver do
  let(:required_permission) { "coupons:update" }
  let(:query) do
    <<~GQL
      query {
        selectableBillableMetrics(limit: 5) {
          collection { id name code }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", %w[coupons:view coupons:update wallets:create wallets:update]

  it "returns a list of billable metrics with minimal fields" do
    metric = create(:billable_metric, organization:)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    collection = result["data"]["selectableBillableMetrics"]["collection"]

    expect(collection.count).to eq(organization.billable_metrics.count)
    expect(collection.first["id"]).to eq(metric.id)
    expect(collection.first["name"]).to eq(metric.name)
    expect(collection.first["code"]).to eq(metric.code)

    expect(result["data"]["selectableBillableMetrics"]["metadata"]["currentPage"]).to eq(1)
    expect(result["data"]["selectableBillableMetrics"]["metadata"]["totalCount"]).to eq(1)
  end
end
