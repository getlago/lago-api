# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Destroy do
  let(:required_permission) { "developers:manage" }
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

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:manage"

  it "destroys a webhook_endpoint" do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: webhook_endpoint.id}}
      )
    end.to change(WebhookEndpoint, :count).by(-1)
  end
end
