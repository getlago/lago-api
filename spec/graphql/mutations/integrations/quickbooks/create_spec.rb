# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Quickbooks::Create, :premium do
  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:code) { "quickbooks1" }
  let(:name) { "QuickBooks 1" }
  let(:connection_id) { "quickbooks-test-connection" }
  let(:realm_id) { "1234567890" }
  let(:provider_config_key) { "quickbooks" }
  let(:connection_url) do
    "https://api.nango.dev/connection/#{connection_id}?provider_config_key=#{provider_config_key}"
  end
  let(:response_status) { 200 }
  let(:response_body) { {"connection_config" => {"realmId" => realm_id}}.to_json }
  let(:input) { {code:, name:, connectionId: connection_id} }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateQuickbooksIntegrationInput!) {
        createQuickbooksIntegration(input: $input) {
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

  let(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  before do
    organization.update!(premium_integrations: ["quickbooks"])
    stub_request(:get, connection_url).to_return(status: response_status, body: response_body)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  context "with valid input" do
    it "creates a QuickBooks integration with the realm id from Nango" do
      expect { result }.to change(Integrations::QuickbooksIntegration, :count).by(1)

      result_data = result["data"]["createQuickbooksIntegration"]
      integration = Integrations::QuickbooksIntegration.find(result_data["id"])

      expect(result_data["code"]).to eq(code)
      expect(result_data["name"]).to eq(name)
      expect(result_data["connectionId"]).to eq(connection_id)
      expect(result_data["realmId"]).to eq(realm_id)
      expect(result_data["sandbox"]).to be(false)
      expect(result_data["syncInvoices"]).to be(false)
      expect(result_data["syncCreditNotes"]).to be(false)
      expect(result_data["syncPayments"]).to be(false)
      expect(integration.organization).to eq(organization)
      expect(integration.settings).not_to have_key("connection_id")
      expect(integration.connection_id).to eq(connection_id)
      expect(WebMock).to have_requested(:get, connection_url).once
    end

    it "enqueues a sync job" do
      expect { result }.to have_enqueued_job(Integrations::Aggregator::PerformSyncJob)
    end

    it_behaves_like "produces a security log", "integration.created" do
      before { result }
    end

    context "with the sync flags" do
      let(:input) do
        {code:, name:, connectionId: connection_id, syncInvoices: true, syncCreditNotes: false, syncPayments: true}
      end

      it "returns the given flags" do
        result_data = result["data"]["createQuickbooksIntegration"]

        expect(result_data["syncInvoices"]).to be(true)
        expect(result_data["syncCreditNotes"]).to be(false)
        expect(result_data["syncPayments"]).to be(true)
      end
    end

    context "with sandbox true" do
      let(:provider_config_key) { "quickbooks-sandbox" }
      let(:input) { {code:, name:, connectionId: connection_id, sandbox: true} }

      it "reads the connection from the quickbooks-sandbox provider config" do
        result_data = result["data"]["createQuickbooksIntegration"]

        expect(result_data["sandbox"]).to be(true)
        expect(result_data["realmId"]).to eq(realm_id)
        expect(WebMock).to have_requested(:get, connection_url).once
      end
    end
  end

  context "when Nango answers 500" do
    let(:response_status) { 500 }
    let(:response_body) { {"error" => "fake-nango-error-body"}.to_json }

    it "returns a third party error and stores nothing" do
      expect { result }.not_to change(Integrations::QuickbooksIntegration, :count)

      expect_graphql_error(result:, message: "third_party_error")
      expect(result["data"]["createQuickbooksIntegration"]).to be_nil
      expect(result.to_h.to_json).not_to include("fake-nango-error-body")
    end
  end

  context "when Nango does not know the connection in this environment" do
    let(:response_status) { 404 }
    let(:response_body) { {"error" => "fake-nango-error-body"}.to_json }

    it "returns a third party error saying the connection was not found and stores nothing" do
      expect { result }.not_to change(Integrations::QuickbooksIntegration, :count)

      expect_graphql_error(
        result:,
        message: "third_party_error",
        details: {error: "Nango: connection_not_found - QuickBooks connection not found for this environment"}
      )
      expect(result.to_h.to_json).not_to include("fake-nango-error-body")
    end
  end

  context "when Nango returns no realm id" do
    let(:response_body) { {"connection_config" => {}}.to_json }

    it "returns a third party error naming the missing company id and stores nothing" do
      expect { result }.not_to change(Integrations::QuickbooksIntegration, :count)

      expect_graphql_error(
        result:,
        message: "third_party_error",
        details: {error: "Nango: realm_id_missing - QuickBooks connection has no company id"}
      )
    end
  end

  context "when the realm id is already used in the organization" do
    before { create(:quickbooks_integration, organization:, code: "quickbooks_existing", settings: {realm_id:}) }

    it "returns a validation error on realmId" do
      expect { result }.not_to change(Integrations::QuickbooksIntegration, :count)

      expect_unprocessable_entity(result, details: {realmId: ["value_already_exist"]})
      expect(result["errors"].first["extensions"]["status"]).to eq(422)
    end
  end

  context "when the realm id is used in another organization" do
    before { create(:quickbooks_integration, organization: create(:organization), code:, settings: {realm_id:}) }

    it "creates the integration" do
      expect { result }.to change(Integrations::QuickbooksIntegration, :count).by(1)

      expect(result["errors"]).to be_nil
      expect(result["data"]["createQuickbooksIntegration"]["realmId"]).to eq(realm_id)
    end
  end

  context "without the quickbooks premium integration" do
    before { organization.update!(premium_integrations: ["xero"]) }

    it "returns premium_integration_missing" do
      expect { result }.not_to change(Integrations::QuickbooksIntegration, :count)

      expect_graphql_error(result:, message: "premium_integration_missing")
      expect(result["errors"].first["extensions"]["status"]).to eq(403)
      expect(WebMock).not_to have_requested(:get, connection_url)
    end
  end
end
