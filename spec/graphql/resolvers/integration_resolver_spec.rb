# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::IntegrationResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "organization:integrations:view" }
  let(:organization) { membership.organization }
  let(:netsuite_integration) { create(:netsuite_integration, organization:) }
  let(:query) do
    <<~GQL
      query($integrationId: ID!) {
        integration(id: $integrationId) {
          ... on NetsuiteIntegration {
            id
            code
            name
            scriptEndpointUrl
            __typename
          }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    customer
    netsuite_integration
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:view"

  it "returns a single integration" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {integrationId: netsuite_integration.id}
    )

    integration_response = result["data"]["integration"]

    expect(integration_response["id"]).to eq(netsuite_integration.id)
    expect(integration_response["code"]).to eq(netsuite_integration.code)
    expect(integration_response["name"]).to eq(netsuite_integration.name)
    expect(integration_response["scriptEndpointUrl"]).to eq(netsuite_integration.script_endpoint_url)
  end

  context "when integration is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {integrationId: "foo"}
      )

      expect_graphql_error(
        result:,
        message: "Resource not found"
      )
    end
  end

  context "with a persisted QuickBooks integration" do
    let(:quickbooks_integration) do
      create(
        :quickbooks_integration,
        organization:,
        settings: {realm_id: "1234567890", sandbox: true, sync_invoices: true, sync_credit_notes: false, sync_payments: true}
      )
    end
    let(:query) do
      <<~GQL
        query($integrationId: ID!) {
          integration(id: $integrationId) {
            __typename
            ... on QuickbooksIntegration {
              id code name connectionId realmId sandbox syncInvoices syncCreditNotes syncPayments
            }
          }
        }
      GQL
    end

    it "returns the QuickBooks integration" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {integrationId: quickbooks_integration.id}
      )

      expect(result["errors"]).to be_nil
      expect(result["data"]["integration"]).to eq(
        {
          "__typename" => "QuickbooksIntegration",
          "id" => quickbooks_integration.id,
          "code" => "quickbooks",
          "name" => "QuickBooks Integration",
          "connectionId" => "quickbooks-test-connection",
          "realmId" => "1234567890",
          "sandbox" => true,
          "syncInvoices" => true,
          "syncCreditNotes" => false,
          "syncPayments" => true
        }
      )
    end
  end
end
