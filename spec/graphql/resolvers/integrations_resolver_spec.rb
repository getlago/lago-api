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
    let(:query) do
      <<~GQL
        query {
          integrations(limit: 5, types: [quickbooks]) {
            collection {
              ... on QuickbooksIntegration { id }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end
    let(:quickbooks_integration) { create(:quickbooks_integration, organization:) }

    # The organization already has a NetSuite and a Xero integration from the top-level setup.
    before do
      quickbooks_integration
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

      expect(integrations_response["collection"]).to eq([{"id" => quickbooks_integration.id}])
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

  context "when types is agent_storefront" do
    let(:agent_storefront_integration) { create(:agent_storefront_integration, organization:, code: "acme_api", name: "Acme API") }
    let(:plan) { create(:plan, organization:, code: "count_per_call", name: "Count per call", amount_cents: 0, amount_currency: "USD") }
    let(:gone_plan) { create(:plan, organization:, code: "gone", amount_cents: 0) }
    let(:query) do
      <<~GQL
        query {
          integrations(limit: 5, types: [agent_storefront]) {
            collection {
              ... on AgentStorefrontIntegration {
                id
                code
                name
                scope
                paymentProviderCode
                paymentProvider { code sellerProfile }
                agentUrl
                authDocumentUrl
                billingDocumentUrl
                claimUrl
                plans { planCode minimumTopupCents maximumTopupCents freeCreditsCents plan { code name amountCurrency } }
                hasEnrolledAgents
                hasAgentsWithStripeCustomer
                __typename
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    before do
      agent_storefront_integration.update!(plans: [
        {plan_code: plan.code, minimum_topup_cents: 500, maximum_topup_cents: 10_000},
        {plan_code: gone_plan.code, free_credits_cents: 1000}
      ])
      # A plan sold then deleted: its row stays in the settings without a plan behind it.
      gone_plan.discard!
    end

    it "returns the agent storefront integrations" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:
      )

      integrations_response = result["data"]["integrations"]

      storefront = agent_storefront_integration
      expect(integrations_response["collection"]).to eq([
        {
          "id" => storefront.id,
          "code" => "acme_api",
          "name" => "Acme API",
          "scope" => "acme_api:use",
          "paymentProviderCode" => storefront.payment_provider_code,
          "paymentProvider" => {"code" => storefront.payment_provider_code, "sellerProfile" => nil},
          "agentUrl" => "#{ENV["LAGO_API_URL"]}/agents/v1/#{storefront.id}",
          "authDocumentUrl" => "#{ENV["LAGO_API_URL"]}/agents/v1/#{storefront.id}/AUTH.md",
          "billingDocumentUrl" => "#{ENV["LAGO_API_URL"]}/agents/v1/#{storefront.id}/BILLING.md",
          "claimUrl" => "#{Rails.application.config.lago_front_url}/agent-claim/#{storefront.id}",
          "plans" => [
            {
              "planCode" => "count_per_call",
              "minimumTopupCents" => "500",
              "maximumTopupCents" => "10000",
              "freeCreditsCents" => nil,
              "plan" => {"code" => "count_per_call", "name" => "Count per call", "amountCurrency" => "USD"}
            },
            # A plan deleted after it was sold keeps its row, without a plan to show.
            {"planCode" => "gone", "minimumTopupCents" => nil, "maximumTopupCents" => nil, "freeCreditsCents" => "1000", "plan" => nil}
          ],
          "hasEnrolledAgents" => false,
          "hasAgentsWithStripeCustomer" => false,
          "__typename" => "AgentStorefrontIntegration"
        }
      ])
      expect(integrations_response["metadata"]["totalCount"]).to eq(1)
    end
  end
end
