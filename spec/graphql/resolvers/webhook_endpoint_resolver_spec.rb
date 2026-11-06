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

  describe "signing keys" do
    subject(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions:,
        query: signing_keys_query,
        variables: {webhookEndpointId: webhook_endpoint.id}
      )
    end

    let(:permissions) { ["developers:manage", "developers:keys:manage"] }
    let(:webhook_endpoint) { build(:webhook_endpoint, organization:, signature_algo:) }
    let(:signature_algo) { :standard_webhooks }
    let(:signing_keys_query) do
      <<~GQL
        query($webhookEndpointId: ID!) {
          webhookEndpoint(id: $webhookEndpointId) {
            id
            webhookUrl
            signingKeys { id secretKey createdAt }
          }
        }
      GQL
    end

    context "when the endpoint signs with Standard Webhooks" do
      let(:newer_key) { travel_to(1.hour.ago) { create(:webhook_endpoint_signing_key, webhook_endpoint:) } }
      let(:older_key) { travel_to(2.hours.ago) { create(:webhook_endpoint_signing_key, webhook_endpoint:) } }

      before do
        newer_key
        older_key
      end

      it "returns the signing keys, oldest first" do
        expect(result["data"]["webhookEndpoint"]["signingKeys"]).to eq(
          [
            {"id" => older_key.id, "secretKey" => older_key.secret, "createdAt" => older_key.created_at.iso8601},
            {"id" => newer_key.id, "secretKey" => newer_key.secret, "createdAt" => newer_key.created_at.iso8601}
          ]
        )
        expect(older_key.secret).to start_with("whsec_")
      end

      context "when the user cannot manage keys" do
        let(:permissions) { "developers:manage" }

        it "returns null signing keys and the other fields" do
          webhook_endpoint_response = result["data"]["webhookEndpoint"]

          expect(webhook_endpoint_response["signingKeys"]).to be_nil
          expect(webhook_endpoint_response["id"]).to eq(webhook_endpoint.id)
          expect(webhook_endpoint_response["webhookUrl"]).to eq(webhook_endpoint.webhook_url)
        end
      end

      context "when the same document also reads the endpoint list" do
        let(:signing_keys_query) do
          <<~GQL
            query($webhookEndpointId: ID!) {
              webhookEndpoint(id: $webhookEndpointId) { signingKeys { id } }
              endpoints: webhookEndpoints { collection { ...EndpointKeys } }
            }

            fragment EndpointKeys on WebhookEndpoint { id signingKeys { id } }
          GQL
        end

        it "returns the signing keys on the single endpoint only" do
          expect(result["data"]["webhookEndpoint"]["signingKeys"]).to eq(
            [{"id" => older_key.id}, {"id" => newer_key.id}]
          )
          expect(result["data"]["endpoints"]["collection"]).to match_array(
            WebhookEndpoint.where(organization:).map { {"id" => it.id, "signingKeys" => nil} }
          )
          expect(WebhookEndpoint.where(organization:)).to include(webhook_endpoint)
        end
      end
    end

    context "when the endpoint signs with JWT and kept a key" do
      let(:signature_algo) { :jwt }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      it "returns an empty list" do
        expect(result["data"]["webhookEndpoint"]["signingKeys"]).to eq([])
      end
    end

    context "when the endpoint signs with HMAC and kept a key" do
      let(:signature_algo) { :hmac }

      before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      it "returns an empty list" do
        expect(result["data"]["webhookEndpoint"]["signingKeys"]).to eq([])
      end
    end
  end

  context "when the endpoint belongs to another organization" do
    let(:other_webhook_endpoint) { create(:webhook_endpoint, organization: create(:organization), signature_algo: :standard_webhooks) }

    before { create(:webhook_endpoint_signing_key, webhook_endpoint: other_webhook_endpoint) }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: ["developers:manage", "developers:keys:manage"],
        query:,
        variables: {webhookEndpointId: other_webhook_endpoint.id}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
