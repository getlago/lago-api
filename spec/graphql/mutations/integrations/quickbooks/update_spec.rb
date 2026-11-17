# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Quickbooks::Update, :premium do
  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:update" }
  let(:code) { "quickbooks_updated" }
  let(:name) { "QuickBooks updated" }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateQuickbooksIntegrationInput!) {
        updateQuickbooksIntegration(input: $input) {
          id,
          code,
          name,
          connectionId,
          realmId,
          sandbox,
          syncInvoices,
          syncCreditNotes,
          syncPayments
        }
      }
    GQL
  end
  let(:integration) do
    create(
      :quickbooks_integration,
      organization:,
      settings: {realm_id: "1234567890", sandbox: true, sync_invoices: false, sync_credit_notes: false, sync_payments: false}
    )
  end
  let(:input) do
    {id: integration.id, name:, code:, syncInvoices: true, syncCreditNotes: true, syncPayments: true}
  end
  let(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let_it_be(:organization, refind: true) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership, refind: true) { create_default(:membership) }

  before do
    integration
    membership.organization.update!(premium_integrations: ["quickbooks"])
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  context "with valid input" do
    it "updates the name, the code and the sync flags" do
      result_data = result["data"]["updateQuickbooksIntegration"]

      expect(result_data["id"]).to eq(integration.id)
      expect(result_data["name"]).to eq(name)
      expect(result_data["code"]).to eq(code)
      expect(result_data["syncInvoices"]).to be(true)
      expect(result_data["syncCreditNotes"]).to be(true)
      expect(result_data["syncPayments"]).to be(true)
    end

    it "keeps the connection id, sandbox and the realm id" do
      result_data = result["data"]["updateQuickbooksIntegration"]
      integration.reload

      expect(result_data["connectionId"]).to eq("quickbooks-test-connection")
      expect(result_data["sandbox"]).to be(true)
      expect(result_data["realmId"]).to eq("1234567890")
      expect(integration.connection_id).to eq("quickbooks-test-connection")
      expect(integration.sandbox).to be(true)
      expect(integration.realm_id).to eq("1234567890")
    end

    it_behaves_like "produces a security log", "integration.updated" do
      before { result }
    end
  end

  context "when the sync flags are set to false" do
    let(:integration) do
      create(
        :quickbooks_integration,
        organization:,
        settings: {realm_id: "1234567890", sandbox: true, sync_invoices: true, sync_credit_notes: true, sync_payments: true}
      )
    end
    let(:input) { {id: integration.id, syncInvoices: false, syncCreditNotes: true} }

    it "stores false and keeps the flag that was not passed" do
      result_data = result["data"]["updateQuickbooksIntegration"]

      expect(result_data["syncInvoices"]).to be(false)
      expect(result_data["syncCreditNotes"]).to be(true)
      expect(result_data["syncPayments"]).to be(true)

      integration.reload
      expect(integration.sync_invoices).to be(false)
      expect(integration.sync_credit_notes).to be(true)
      expect(integration.sync_payments).to be(true)
    end
  end

  context "when the input sets connectionId" do
    let(:input) { {id: integration.id, connectionId: "other-connection"} }

    it "is refused by the schema" do
      expect(result["errors"].first["message"]).to include("connectionId")
      expect(integration.reload.connection_id).to eq("quickbooks-test-connection")
    end
  end

  context "when the input sets sandbox" do
    let(:input) { {id: integration.id, sandbox: false} }

    it "is refused by the schema" do
      expect(result["errors"].first["message"]).to include("sandbox")
      expect(integration.reload.sandbox).to be(true)
    end
  end

  it "has no connectionId or sandbox input field" do
    introspection = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: '{ __type(name: "UpdateQuickbooksIntegrationInput") { inputFields { name } } }'
    )

    names = introspection["data"]["__type"]["inputFields"].map { |field| field["name"] }
    expect(names).to contain_exactly(
      "clientMutationId", "id", "code", "name", "syncCreditNotes", "syncInvoices", "syncPayments"
    )
  end

  context "with a Xero integration id" do
    let(:xero_integration) { create(:xero_integration, organization:) }
    let(:input) { {id: xero_integration.id, name:} }

    it "returns not found and leaves the Xero integration unchanged" do
      expect_not_found(result)
      expect(xero_integration.reload.name).not_to eq(name)
    end
  end

  context "with an integration of another organization" do
    let(:integration) { create(:quickbooks_integration, organization: create(:organization)) }

    it "returns not found" do
      expect_not_found(result)
      expect(integration.reload.name).not_to eq(name)
    end
  end

  context "without the quickbooks premium integration" do
    before { membership.organization.update!(premium_integrations: ["xero"]) }

    it "returns premium_integration_missing" do
      expect_graphql_error(result:, message: "premium_integration_missing")
      expect(result["errors"].first["extensions"]["status"]).to eq(403)
      expect(integration.reload.name).not_to eq(name)
    end
  end
end
