# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Create, type: :graphql do
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

  it "creates a webhook_endpoint" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {input:}
    )

    expect(result["data"]["createWebhookEndpoint"]).to include(
      "id" => String,
      "webhookUrl" => webhook_url,
      "signatureAlgo" => "hmac"
    )
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {input:}
      )

      expect_unauthorized_error(result)
    end
  end

  context "without current organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {input:}
      )

      expect_forbidden_error(result)
    end
  end
end
