# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::WebhookEndpoints::Destroy do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {input: {id: webhook_endpoint.id}}
    )
  end

  include_context "with mocked security logger"

  let(:query) do
    <<-GQL
      mutation($input: DestroyWebhookEndpointInput!) {
        destroyWebhookEndpoint(input: $input) { id }
      }
    GQL
  end
  let(:required_permission) { "developers:manage" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let!(:webhook_endpoint) { create(:webhook_endpoint, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "developers:manage"

  context "when webhook endpoint exists in the current organization" do
    it "destroys the webhook endpoint" do
      expect { result }.to change(WebhookEndpoint, :count).by(-1)
    end

    it "produces a security log" do
      result

      expect(security_logger).to have_received(:produce).with(
        organization: organization,
        log_type: "webhook_endpoint",
        log_event: "webhook_endpoint.deleted",
        resources: {webhook_url: webhook_endpoint.webhook_url, signature_algo: "jwt"}
      )
    end
  end
end
