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

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }

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

  context "when signatureAlgo is standard_webhooks" do
    subject(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: input.merge(signatureAlgo: "standard_webhooks")}
      )
    end

    it "refuses it without the standard_webhooks_signature flag" do
      expect { result }.not_to change(WebhookEndpoint, :count)

      expect_unprocessable_entity(result, details: {signatureAlgo: ["value_is_invalid"]})
    end

    context "with the standard_webhooks_signature flag" do
      before { organization.enable_feature_flag!(:standard_webhooks_signature) }

      it "creates a standard_webhooks endpoint with one signing key" do
        expect(result["data"]["createWebhookEndpoint"]).to include("signatureAlgo" => "standard_webhooks")
        webhook_endpoint = WebhookEndpoint.find(result["data"]["createWebhookEndpoint"]["id"])
        expect(webhook_endpoint.signature_algo).to eq("standard_webhooks")
        expect(webhook_endpoint.signing_keys.count).to eq(1)
      end
    end
  end
end
