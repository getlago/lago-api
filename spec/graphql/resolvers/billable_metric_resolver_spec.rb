# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::BillableMetricResolver do
  subject(:graphql_request) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {billableMetricId: billable_metric.id}
    )
  end

  let(:required_permission) { "billable_metrics:view" }
  let(:query) do
    <<~GQL
      query($billableMetricId: ID!) {
        billableMetric(id: $billableMetricId) {
          id
          name
          hasSubscriptions
          hasActiveSubscriptions
          hasDraftInvoices
          hasPlans
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "billable_metrics:view"

  it "returns a single billable metric" do
    metric_response = graphql_request["data"]["billableMetric"]

    expect(metric_response["id"]).to eq(billable_metric.id)
    expect(metric_response["hasSubscriptions"]).to eq(false)
    expect(metric_response["hasActiveSubscriptions"]).to eq(false)
    expect(metric_response["hasDraftInvoices"]).to eq(false)
    expect(metric_response["hasPlans"]).to eq(false)
  end

  context "when billable metric is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: "foo"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
