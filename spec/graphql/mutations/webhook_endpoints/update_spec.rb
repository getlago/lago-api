# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Update do
  include_context "with mocked security logger"

  let(:required_permission) { "developers:manage" }
  let(:webhook_url) { Faker::Internet.url }
  let(:webhook_endpoint) { create(:webhook_endpoint, organization: membership.organization) }
  let(:input) do
    {
      id: webhook_endpoint.id,
      webhookUrl: webhook_url,
      signatureAlgo: "hmac",
      name: "Updated Webhook",
      eventTypes: ["customer_updated"]
    }
  end
  let(:mutation) do
    <<-GQL
      mutation($input: WebhookEndpointUpdateInput!) {
        updateWebhookEndpoint(input: $input) {
          id,
          webhookUrl,
          signatureAlgo,
          name,
          eventTypes,
          signingKeys { id secretKey createdAt }
        }
      }
    GQL
  end

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }

  before { webhook_endpoint }

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

    it "updates a webhook_endpoint" do
      expect(result["data"]["updateWebhookEndpoint"]).to include(
        "id" => String,
        "webhookUrl" => webhook_url,
        "signatureAlgo" => "hmac",
        "name" => "Updated Webhook",
        "eventTypes" => ["customer_updated"]
      )
    end

    it_behaves_like "produces a security log", "webhook_endpoint.updated"
  end

  context "when signatureAlgo changes to standard_webhooks" do
    subject(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions:,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id, webhookUrl: webhook_endpoint.webhook_url, signatureAlgo: "standard_webhooks"}}
      )
    end

    let(:permissions) { ["developers:manage", "developers:keys:manage"] }

    it "refuses it without the standard_webhooks_signature flag" do
      expect { result }.not_to change { webhook_endpoint.reload.signature_algo }

      expect_unprocessable_entity(result, details: {signatureAlgo: ["value_is_invalid"]})
    end

    context "with the standard_webhooks_signature flag" do
      before { organization.enable_feature_flag!(:standard_webhooks_signature) }

      it "switches the endpoint to standard_webhooks with one signing key" do
        expect(result["data"]["updateWebhookEndpoint"]).to include("signatureAlgo" => "standard_webhooks")
        expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
        expect(webhook_endpoint.signing_keys.count).to eq(1)
      end

      it "returns the signing key of the endpoint" do
        signing_keys = result["data"]["updateWebhookEndpoint"]["signingKeys"]
        signing_key = webhook_endpoint.signing_keys.sole

        expect(signing_keys).to eq(
          [{"id" => signing_key.id, "secretKey" => signing_key.secret, "createdAt" => signing_key.created_at.iso8601}]
        )
        expect(signing_key.secret).to start_with("whsec_")
      end

      context "when the user cannot manage keys" do
        let(:permissions) { "developers:manage" }

        it "returns null signing keys and the other fields" do
          webhook_endpoint_response = result["data"]["updateWebhookEndpoint"]

          expect(webhook_endpoint_response["signingKeys"]).to be_nil
          expect(webhook_endpoint_response["id"]).to eq(webhook_endpoint.id)
          expect(webhook_endpoint_response["signatureAlgo"]).to eq("standard_webhooks")
        end
      end
    end
  end

  context "when a standard_webhooks endpoint switches back to jwt" do
    subject(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions:,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id, webhookUrl: webhook_endpoint.webhook_url, signatureAlgo: "jwt"}}
      )
    end

    let(:permissions) { ["developers:manage", "developers:keys:manage"] }
    let(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }
    let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

    before { signing_key }

    it "returns an empty list of signing keys and keeps the key" do
      expect(result["data"]["updateWebhookEndpoint"]).to include("signatureAlgo" => "jwt", "signingKeys" => [])
      expect(webhook_endpoint.signing_keys.reload).to eq([signing_key])
    end
  end

  context "when a standard_webhooks endpoint of an organization without the flag is renamed" do
    subject(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions:,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id, webhookUrl: webhook_url, name: "Renamed"}}
      )
    end

    let(:permissions) { ["developers:manage", "developers:keys:manage"] }
    let(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }
    let(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

    before { signing_key }

    it "updates the name" do
      expect(result["data"]["updateWebhookEndpoint"]).to include("name" => "Renamed", "signatureAlgo" => "standard_webhooks")
      expect(webhook_endpoint.reload.name).to eq("Renamed")
    end

    it "returns the signing keys without the flag" do
      expect(organization.feature_flag_enabled?(:standard_webhooks_signature)).to be(false)
      expect(result["data"]["updateWebhookEndpoint"]["signingKeys"]).to eq(
        [{"id" => signing_key.id, "secretKey" => signing_key.secret, "createdAt" => signing_key.created_at.iso8601}]
      )
    end
  end
end
