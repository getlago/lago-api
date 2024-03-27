# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WebhookEndpointResolver, type: :graphql do
  let(:query) do
    <<-GQL
      query($webhookEndpointId: ID!) {
        webhookEndpoint(id: $webhookEndpointId) {
          id
          webhookUrl
          createdAt
          updatedAt
          organization { id name }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:webhook_endpoint) { build(:webhook_endpoint, organization:) }
  let(:organization) { membership.organization }

  before do
    organization.webhook_endpoints << webhook_endpoint
  end

  it "returns a single credit note" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {
        webhookEndpointId: webhook_endpoint.id
      }
    )

    webhook_endpoint_response = result["data"]["webhookEndpoint"]

    aggregate_failures do
      expect(webhook_endpoint_response["id"]).to eq(webhook_endpoint.id)
    end
  end
end
