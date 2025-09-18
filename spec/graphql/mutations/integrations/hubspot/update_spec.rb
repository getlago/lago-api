# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Hubspot::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:hubspot_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:code) { "hubspot1" }
  let(:name) { "Hubspot 1" }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateHubspotIntegrationInput!) {
        updateHubspotIntegration(input: $input) {
          id,
          code,
          name,
          connectionId,
          defaultTargetedObject,
          syncInvoices,
          syncSubscriptions
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ["hubspot"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a hubspot integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration.id,
          name:,
          code:
        }
      }
    )

    result_data = result["data"]["updateHubspotIntegration"]

    aggregate_failures do
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
    end
  end
end
