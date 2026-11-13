# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::WebhookEndpointsResolver do
  let(:required_permission) { "developers:manage" }
  let(:query) do
    <<~GQL
      query {
        webhookEndpoints(limit: 5) {
          collection { id webhookUrl signatureAlgo name eventTypes }
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

  context "when an endpoint signs with Standard Webhooks and the user can manage keys" do
    let(:query) do
      <<~GQL
        query {
          webhookEndpoints(limit: 5) {
            collection { id signingKeys { id secretKey } }
          }
        }
      GQL
    end
    let(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }

    before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

    it "returns null signing keys without reading them" do
      result = nil
      sqls = []
      subscriber = ->(*, payload) { sqls << payload[:sql] }

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: ["developers:manage", "developers:keys:manage"],
          query:
        )
      end

      # The organization factory also creates a JWT endpoint.
      expect(result["data"]["webhookEndpoints"]["collection"]).to match_array(
        WebhookEndpoint.where(organization:).map { {"id" => it.id, "signingKeys" => nil} }
      )
      expect(WebhookEndpoint.where(organization:)).to include(webhook_endpoint)
      expect(sqls).to be_present
      expect(sqls.grep(/webhook_endpoint_signing_keys/)).to eq([])
    end
  end
end
