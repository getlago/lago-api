# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WebhooksResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        webhooks(limit: 5, webhookEndpointId: "#{webhook_endpoint.id}") {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:webhook_endpoint) { create(:webhook_endpoint) }
  let(:organization) { webhook_endpoint.organization.reload }
  let(:membership) { create(:membership, organization:) }

  before do
    create_list(:webhook, 5, :succeeded, webhook_endpoint:)
  end

  it "returns a list of webhooks" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:
    )

    webhooks_response = result["data"]["webhooks"]

    aggregate_failures do
      expect(webhooks_response["collection"].count).to eq(webhook_endpoint.webhooks.count)
      expect(webhooks_response["metadata"]["currentPage"]).to eq(1)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query:
      )

      expect_graphql_error(
        result:,
        message: "Missing organization id"
      )
    end
  end

  context "when not member of the organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:
      )

      expect_graphql_error(
        result:,
        message: "Not in organization"
      )
    end
  end
end
