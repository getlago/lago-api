# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Salesforce::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration) { create(:salesforce_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:name) { "Salesforce 1" }
  let(:code) { "salesforce_work" }
  let(:instance_id) { "salesforce_link" }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateSalesforceIntegrationInput!) {
        updateSalesforceIntegration(input: $input) {
          id,
          code,
          name,
          instanceId
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  before do
    integration
    membership.organization.update!(premium_integrations: ["salesforce"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a salesforce integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration.id,
          name:,
          code: code,
          instanceId: instance_id
        }
      }
    )

    result_data = result["data"]["updateSalesforceIntegration"]

    aggregate_failures do
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
      expect(result_data["instanceId"]).to eq(instance_id)
    end
  end
end
