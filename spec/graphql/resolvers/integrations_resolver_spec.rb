# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::IntegrationsResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "customers:view" }
  let(:organization) { membership.organization }
  let(:netsuite_integration) { create(:netsuite_integration, organization:) }
  let(:xero_integration) { create(:xero_integration, organization:) }
  let(:query) do
    <<~GQL
      query {
        integrations(limit: 5) {
          collection {
            ... on NetsuiteIntegration {
              id
              code
              __typename
            }
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }

  before do
    netsuite_integration
    xero_integration
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", %w[customers:view organization:integrations:view]

  context "when types is present" do
    let(:query) do
      <<~GQL
        query {
          integrations(limit: 5, types: [netsuite]) {
            collection {
              ... on NetsuiteIntegration {
                id
                code
                __typename
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it "returns a list of integrations" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      integrations_response = result["data"]["integrations"]

      expect(integrations_response["collection"].count).to eq(1)
      expect(integrations_response["collection"].first["id"]).to eq(netsuite_integration.id)

      expect(integrations_response["metadata"]["currentPage"]).to eq(1)
      expect(integrations_response["metadata"]["totalCount"]).to eq(1)
    end
  end

  context "when types is quickbooks" do
    # Only the metadata is selected: the Integration union has no QuickBooks member yet, so
    # resolving the collection would raise on a QuickBooks row.
    let(:query) do
      <<~GQL
        query {
          integrations(limit: 5, types: [quickbooks]) {
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    # The organization already has a NetSuite and a Xero integration from the top-level setup.
    before do
      create(:quickbooks_integration, organization:)
      create(:quickbooks_integration, organization: create(:organization))
    end

    it "returns only the organization's QuickBooks integrations" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect(result["errors"]).to be_nil

      integrations_response = result["data"]["integrations"]

      expect(integrations_response["metadata"]["currentPage"]).to eq(1)
      expect(integrations_response["metadata"]["totalCount"]).to eq(1)
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
        query {
          integrations(limit: 5, types: [quickbooks]) {
            collection {
              __typename
              ... on QuickbooksIntegration {
                id code name connectionId realmId sandbox syncInvoices syncCreditNotes syncPayments
              }
            }
            metadata { totalCount }
          }
        }
      GQL
    end

    before { quickbooks_integration }

    it "returns the QuickBooks integration" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      expect(result["errors"]).to be_nil

      integrations_response = result["data"]["integrations"]

      expect(integrations_response["collection"]).to eq(
        [
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
        ]
      )
      expect(integrations_response["metadata"]["totalCount"]).to eq(1)
    end
  end
end
