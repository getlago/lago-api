# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Create do
  let(:required_permission) { "developers:manage" }
  let(:membership) { create(:membership) }
  let(:webhook_url) { Faker::Internet.url }

  let(:input) do
    {
      webhookUrl: webhook_url,
      signatureAlgo: "hmac"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: WebhookEndpointCreateInput!) {
        createWebhookEndpoint(input: $input) {
          id,
          webhookUrl,
          signatureAlgo,
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:manage"

  it "creates a webhook_endpoint" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )

    expect(result["data"]["createWebhookEndpoint"]).to include(
      "id" => String,
      "webhookUrl" => webhook_url,
      "signatureAlgo" => "hmac"
    )
  end
end
