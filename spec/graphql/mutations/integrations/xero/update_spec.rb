# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Xero::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:xero_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:code) { "xero1" }
  let(:name) { "Xero 1" }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateXeroIntegrationInput!) {
        updateXeroIntegration(input: $input) {
          id,
          code,
          name,
          syncInvoices,
          syncCreditNotes,
          syncPayments
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ["xero"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a xero integration" do
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

    result_data = result["data"]["updateXeroIntegration"]

    aggregate_failures do
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
    end
  end
end
