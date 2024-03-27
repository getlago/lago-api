# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:webhook_endpoint) { create(:webhook_endpoint, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyWebhookEndpointInput!) {
        destroyWebhookEndpoint(input: $input) { id }
      }
    GQL
  end

  before { webhook_endpoint }

  it "destroys a webhook_endpoint" do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id}}
      )
    end.to change(WebhookEndpoint, :count).by(-1)
  end

  context "without current_organization" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id}}
      )

      expect_forbidden_error(result)
    end
  end

  context "without current_user" do
    it "returns an error" do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id}}
      )

      expect_unauthorized_error(result)
    end
  end
end
