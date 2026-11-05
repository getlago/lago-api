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
          eventTypes
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership, refind: true) { create_default(:membership) }

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

  context "when switching to Standard Webhooks" do
    let(:webhook_endpoint) { create(:webhook_endpoint, organization: membership.organization) }
    let(:input) { {id: webhook_endpoint.id, webhookUrl: webhook_url, name: "Updated Webhook", signatureAlgo: "standard_webhooks"} }
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
      expect { result }.not_to change { webhook_endpoint.reload.attributes }

      expect_unprocessable_entity(result, details: {signatureAlgo: ["value_is_invalid"]})
    end

    context "when the organization has the standard_webhooks_signature flag" do
      before { membership.organization.enable_feature_flag!(:standard_webhooks_signature) }

      it "switches the webhook_endpoint to Standard Webhooks" do
        expect(result["data"]["updateWebhookEndpoint"]).to include(
          "id" => webhook_endpoint.id,
          "signatureAlgo" => "standard_webhooks"
        )
      end

      it "creates a signing key" do
        expect { result }.to change(webhook_endpoint.signing_keys, :count).from(0).to(1)
      end
    end

    context "when the endpoint already uses Standard Webhooks" do
      let(:webhook_endpoint) do
        create(:webhook_endpoint, :legacy_signature_algo, organization: membership.organization, signature_algo: "standard_webhooks")
      end

      it "accepts it again without the rollout flag" do
        expect(result["data"]["updateWebhookEndpoint"]).to include(
          "id" => webhook_endpoint.id,
          "name" => "Updated Webhook",
          "signatureAlgo" => "standard_webhooks"
        )
      end

      context "with a signing key" do
        let(:webhook_endpoint) do
          create(:webhook_endpoint, :standard_webhooks, organization: membership.organization)
        end

        it "keeps the existing signing key" do
          signing_key_ids = webhook_endpoint.signing_keys.pluck(:id)

          expect(result["data"]["updateWebhookEndpoint"]).to include("signatureAlgo" => "standard_webhooks")
          expect(webhook_endpoint.signing_keys.reload.pluck(:id)).to eq(signing_key_ids)
          expect(signing_key_ids.size).to eq(1)
        end
      end
    end
  end
end
