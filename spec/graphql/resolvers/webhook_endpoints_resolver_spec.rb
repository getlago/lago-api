# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WebhookEndpointsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        webhookEndpoints(limit: 5) {
          collection { id webhookUrl }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it "returns a list of webhook endpoints" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    webhook_endpoints_response = result["data"]["webhookEndpoints"]

    aggregate_failures do
      expect(webhook_endpoints_response["collection"].first).to include(
        "id" => organization.webhook_endpoints.first.id,
        "webhookUrl" => organization.webhook_endpoints.first.webhook_url
      )

      expect(webhook_endpoints_response["metadata"]).to include(
        "currentPage" => 1,
        "totalCount" => 1
      )
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: "Missing organization id")
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:
      )

      expect_graphql_error(result:, message: "Not in organization")
    end
  end
end
