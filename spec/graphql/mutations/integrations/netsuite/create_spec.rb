# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Netsuite::Create do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:code) { "netsuite1" }
  let(:name) { "Netsuite 1" }
  let(:script_endpoint_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateNetsuiteIntegrationInput!) {
        createNetsuiteIntegration(input: $input) {
          id,
          code,
          name,
          clientId,
          clientSecret,
          syncInvoices,
          syncCreditNotes,
          syncPayments,
          scriptEndpointUrl,
          tokenId,
          tokenSecret
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before { membership.organization.update!(premium_integrations: ["netsuite"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates a netsuite integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          code:,
          name:,
          scriptEndpointUrl: script_endpoint_url,
          accountId: "012",
          clientId: "123",
          clientSecret: "456",
          tokenId: "xyz",
          tokenSecret: "zyx",
          connectionId: "this-is-random-uuid"
        }
      }
    )

    result_data = result["data"]["createNetsuiteIntegration"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["code"]).to eq(code)
      expect(result_data["name"]).to eq(name)
      expect(result_data["tokenId"]).to eq("xyz")
      expect(result_data["tokenSecret"]).to eq("••••••••…zyx")
      expect(result_data["scriptEndpointUrl"]).to eq(script_endpoint_url)
    end
  end
end
