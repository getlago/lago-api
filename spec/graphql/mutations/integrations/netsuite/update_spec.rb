# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Netsuite::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:code) { "netsuite1" }
  let(:name) { "Netsuite 1" }
  let(:script_endpoint_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateNetsuiteIntegrationInput!) {
        updateNetsuiteIntegration(input: $input) {
          id,
          code,
          name,
          clientId,
          clientSecret,
          syncInvoices,
          syncCreditNotes,
          syncPayments,
          scriptEndpointUrl
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ["netsuite"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a netsuite integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration.id,
          name:,
          code:,
          scriptEndpointUrl: script_endpoint_url
        }
      }
    )

    result_data = result["data"]["updateNetsuiteIntegration"]

    aggregate_failures do
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
      expect(result_data["scriptEndpointUrl"]).to eq(script_endpoint_url)
    end
  end
end
