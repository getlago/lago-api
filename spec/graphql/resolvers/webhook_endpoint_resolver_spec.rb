# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WebhookEndpointResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "developers:manage" }
  let(:webhook_endpoint) { build(:webhook_endpoint, organization:, event_types: ["customer.created"]) }
  let(:organization) { membership.organization }
  let(:query) do
    <<-GQL
      query($webhookEndpointId: ID!) {
        webhookEndpoint(id: $webhookEndpointId) {
          id
          webhookUrl
          signatureAlgo
          signingKeys { id secretKey createdAt }
          name
          eventTypes
          createdAt
          updatedAt
          organization { id name }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }

  before do
    organization.webhook_endpoints << webhook_endpoint
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:manage"

  it "returns a single credit note" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        webhookEndpointId: webhook_endpoint.id
      }
    )

    webhook_endpoint_response = result["data"]["webhookEndpoint"]

    expect(webhook_endpoint_response["id"]).to eq(webhook_endpoint.id)
    expect(webhook_endpoint_response["webhookUrl"]).to eq(webhook_endpoint.webhook_url)
    expect(webhook_endpoint_response["signatureAlgo"]).to eq(webhook_endpoint.signature_algo)
    expect(webhook_endpoint_response["name"]).to eq(webhook_endpoint.name)
    expect(webhook_endpoint_response["eventTypes"]).to match_array(["customer_created"])
    expect(webhook_endpoint_response["createdAt"]).to eq(webhook_endpoint.created_at.iso8601)
    expect(webhook_endpoint_response["updatedAt"]).to eq(webhook_endpoint.updated_at.iso8601)
    expect(webhook_endpoint_response["organization"]["id"]).to eq(organization.id)
    expect(webhook_endpoint_response["organization"]["name"]).to eq(organization.name)
  end

  describe "signingKeys" do
    subject(:webhook_endpoint_response) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions:,
        query:,
        variables: {webhookEndpointId: webhook_endpoint.id}
      )["data"]["webhookEndpoint"]
    end

    let(:permissions) { %w[developers:manage developers:keys:manage] }

    context "with a standard_webhooks endpoint" do
      let(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }

      it "returns its signing key" do
        signing_key = webhook_endpoint.signing_keys.sole

        expect(webhook_endpoint_response["signingKeys"]).to eq([{"id" => signing_key.id, "secretKey" => signing_key.secret_key, "createdAt" => signing_key.created_at.iso8601}])
        expect(signing_key.secret_key).to match(/\Awhsec_/)
      end

      context "without developers:keys:manage permission" do
        let(:permissions) { "developers:manage" }

        it "returns null signing keys and resolves the other fields" do
          expect(webhook_endpoint_response).to include(
            "id" => webhook_endpoint.id,
            "webhookUrl" => webhook_endpoint.webhook_url,
            "signatureAlgo" => "standard_webhooks",
            "signingKeys" => nil
          )
        end
      end
    end

    context "with an hmac endpoint" do
      let(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :hmac) }

      it "returns no signing keys" do
        expect(webhook_endpoint_response).to include("id" => webhook_endpoint.id, "signingKeys" => [])
      end
    end

    context "with a jwt endpoint that kept a signing key" do
      let(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :jwt) }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      it "returns no signing keys" do
        expect(webhook_endpoint_response).to include("id" => webhook_endpoint.id, "signingKeys" => [])
      end
    end
  end
end
