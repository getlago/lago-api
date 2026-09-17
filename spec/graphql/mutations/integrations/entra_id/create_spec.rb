# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::EntraId::Create, :premium do
  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateEntraIdIntegrationInput!) {
        createEntraIdIntegration(input: $input) {
          id,
          name,
          code,
          clientId,
          clientSecret,
          domain,
          tenantId,
        }
      }
    GQL
  end

  before { membership.organization.update!(premium_integrations: ["entra_id"]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  context "with valid input" do
    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            clientId: "123",
            clientSecret: "456",
            domain: "foo.bar",
            tenantId: "tenant-123"
          }
        }
      )
    end

    it "creates an entra_id integration" do
      result_data = result["data"]["createEntraIdIntegration"]

      expect(result_data["id"]).to be_present
      expect(result_data["code"]).to eq("entra_id")
      expect(result_data["name"]).to eq("Entra ID Integration")
      expect(result_data["tenantId"]).to eq("tenant-123")
    end

    it_behaves_like "produces a security log", "integration.created"
  end
end
