# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Create do
  include_context "with mocked security logger"

  let(:required_permission) { "developers:manage" }
  let(:webhook_url) { Faker::Internet.url }
  let(:input) do
    {
      webhookUrl: webhook_url,
      signatureAlgo: "hmac",
      name: "Test Webhook",
      eventTypes: ["customer_created"]
    }
  end
  let(:mutation) do
    <<-GQL
      mutation($input: WebhookEndpointCreateInput!) {
        createWebhookEndpoint(input: $input) {
          id,
          webhookUrl,
          signatureAlgo,
          name,
          eventTypes
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership, refind: true) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:manage"

  context "with valid input" do
    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )
    end

    it "creates a webhook_endpoint" do
      expect(result["data"]["createWebhookEndpoint"]).to include(
        "id" => String,
        "webhookUrl" => webhook_url,
        "signatureAlgo" => "hmac",
        "name" => "Test Webhook",
        "eventTypes" => ["customer_created"]
      )
    end

    it_behaves_like "produces a security log", "webhook_endpoint.created"
  end

  context "when signing with Standard Webhooks" do
    let(:input) { {webhookUrl: webhook_url, signatureAlgo: "standard_webhooks"} }
    let(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )
    end

    it "is refused without the rollout flag" do
      expect { result }.not_to change(WebhookEndpoint, :count)

      expect_unprocessable_entity(result, details: {signatureAlgo: ["value_is_invalid"]})
    end

    context "when the organization has the standard_webhooks_signature flag" do
      before { membership.organization.enable_feature_flag!(:standard_webhooks_signature) }

      it "creates a webhook_endpoint signed with Standard Webhooks" do
        expect(result["data"]["createWebhookEndpoint"]).to include(
          "webhookUrl" => webhook_url,
          "signatureAlgo" => "standard_webhooks"
        )
      end

      it "creates a signing key for the endpoint" do
        expect { result }.to change(WebhookEndpointSigningKey, :count).by(1)

        endpoint = WebhookEndpoint.find(result["data"]["createWebhookEndpoint"]["id"])
        expect(endpoint.signing_keys.count).to eq(1)
      end
    end
  end
end
