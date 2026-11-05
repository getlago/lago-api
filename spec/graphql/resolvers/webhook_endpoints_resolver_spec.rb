# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WebhookEndpointsResolver do
  let(:required_permission) { "developers:manage" }
  let(:query) do
    <<~GQL
      query {
        webhookEndpoints(limit: 5) {
          collection { id webhookUrl signatureAlgo name eventTypes signingKeys { id secretKey createdAt } }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:manage"

  it "returns a list of webhook endpoints" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    webhook_endpoints_response = result["data"]["webhookEndpoints"]

    expect(webhook_endpoints_response["collection"].first).to include(
      "id" => organization.webhook_endpoints.first.id,
      "webhookUrl" => organization.webhook_endpoints.first.webhook_url,
      "signatureAlgo" => organization.webhook_endpoints.first.signature_algo,
      "name" => organization.webhook_endpoints.first.name,
      "eventTypes" => organization.webhook_endpoints.first.event_types
    )

    expect(webhook_endpoints_response["metadata"]).to include(
      "currentPage" => 1,
      "totalCount" => 1
    )
  end

  context "with standard_webhooks endpoints" do
    subject(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: %w[developers:manage developers:keys:manage],
        query:
      )
    end

    let(:membership) { create(:membership, organization: create(:organization, webhook_url: nil)) }
    let(:first_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }
    let(:second_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }
    let(:hmac_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :hmac) }

    before do
      first_endpoint
      second_endpoint
      create(:webhook_endpoint_signing_key, webhook_endpoint: hmac_endpoint)
    end

    it "returns the signing keys of each standard_webhooks endpoint in one query" do
      statements = capture_sql { result }

      expect(result["data"]["webhookEndpoints"]["collection"].map { it.slice("id", "signingKeys") }).to match_array(
        [
          {"id" => first_endpoint.id, "signingKeys" => [{"id" => first_endpoint.signing_keys.sole.id, "secretKey" => first_endpoint.signing_keys.sole.secret_key, "createdAt" => first_endpoint.signing_keys.sole.created_at.iso8601}]},
          {"id" => second_endpoint.id, "signingKeys" => [{"id" => second_endpoint.signing_keys.sole.id, "secretKey" => second_endpoint.signing_keys.sole.secret_key, "createdAt" => second_endpoint.signing_keys.sole.created_at.iso8601}]},
          {"id" => hmac_endpoint.id, "signingKeys" => []}
        ]
      )
      expect(statements.grep(/FROM "webhook_endpoint_signing_keys"/).size).to eq(1)
    end
  end
end
