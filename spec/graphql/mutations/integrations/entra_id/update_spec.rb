# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::EntraId::Update, :premium do
  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:entra_id_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateEntraIdIntegrationInput!) {
        updateEntraIdIntegration(input: $input) {
          id,
          code,
          name,
          clientId,
          clientSecret,
          domain,
          tenantId,
        }
      }
    GQL
  end

  before do
    integration
    membership.organization.update!(premium_integrations: ["entra_id"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  context "with valid input" do
    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: integration.id,
            domain: "foo.bar",
            tenantId: "tenant-456"
          }
        }
      )
    end

    it "updates an entra_id integration" do
      result_data = result["data"]["updateEntraIdIntegration"]

      expect(result_data["domain"]).to eq("foo.bar")
      expect(result_data["tenantId"]).to eq("tenant-456")
    end

    it_behaves_like "produces a security log", "integration.updated"
  end
end
