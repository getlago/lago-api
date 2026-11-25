# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Quickbooks::VerifyConnection, :premium do
  let(:required_permission) { "organization:integrations:update" }
  let(:mutation) do
    <<-GQL
      mutation($input: VerifyQuickbooksIntegrationConnectionInput!) {
        verifyQuickbooksIntegrationConnection(input: $input) {
          id,
          realmId
        }
      }
    GQL
  end
  let(:mismatch) { nil }
  let(:integration) do
    create(
      :quickbooks_integration,
      organization:,
      settings: {realm_id: "1234567890", realm_id_mismatch: mismatch, sandbox: false}.compact
    )
  end
  let(:input) { {id: integration.id} }
  let(:connection_url) do
    "https://api.nango.dev/connection/quickbooks-test-connection?provider_config_key=quickbooks"
  end
  let(:nango_realm_id) { "1234567890" }
  let(:response_status) { 200 }
  let(:response_body) { {"connection_config" => {"realmId" => nango_realm_id}}.to_json }
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

    stub_request(:get, connection_url)
      .to_return(status: response_status, body: response_body, headers: {"Content-Type" => "application/json"})
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  context "when Nango returns the stored realm id" do
    let(:mismatch) { true }

    it "returns the integration, keeps the realm id and clears the flag" do
      result_data = result["data"]["verifyQuickbooksIntegrationConnection"]

      expect(result["errors"]).to be_nil
      expect(result_data["id"]).to eq(integration.id)
      expect(result_data["realmId"]).to eq("1234567890")

      integration.reload
      expect(integration.realm_id).to eq("1234567890")
      expect(integration.realm_id_mismatch).to be(false)
      expect(WebMock).to have_requested(:get, connection_url).once
    end
  end

  context "when Nango returns another realm id" do
    let(:nango_realm_id) { "9999999999" }

    it "returns realm_id_changed, keeps the realm id and stores the flag" do
      expect(result["data"]["verifyQuickbooksIntegrationConnection"]).to be_nil
      expect(result["errors"].sole).to include(
        "message" => "forbidden",
        "extensions" => {"status" => 403, "code" => "realm_id_changed"}
      )

      integration.reload
      expect(integration.realm_id).to eq("1234567890")
      expect(integration.realm_id_mismatch).to be(true)
    end
  end

  context "when Nango does not know the connection" do
    let(:mismatch) { true }
    let(:response_status) { 404 }
    let(:response_body) { {"error" => "fake-nango-error-body"}.to_json }

    it "returns the ConnectionService error and leaves the flag as it was" do
      expect_graphql_error(
        result:,
        message: "third_party_error",
        details: {error: "Nango: connection_not_found - QuickBooks connection not found for this environment"}
      )
      expect(result.to_h.to_json).not_to include("fake-nango-error-body")

      integration.reload
      expect(integration.realm_id).to eq("1234567890")
      expect(integration.realm_id_mismatch).to be(true)
    end
  end

  context "when the input has no id" do
    let(:input) { {} }

    it "is refused by the schema" do
      expect(result["errors"].first["message"]).to include("id")
      expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
    end
  end

  it "has only an id input field" do
    introspection = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: '{ __type(name: "VerifyQuickbooksIntegrationConnectionInput") { inputFields { name } } }'
    )

    names = introspection["data"]["__type"]["inputFields"].map { |field| field["name"] }
    expect(names).to contain_exactly("clientMutationId", "id")
  end

  context "with a Xero integration id" do
    let(:xero_integration) { create(:xero_integration, organization:) }
    let(:input) { {id: xero_integration.id} }

    it "returns not found without asking Nango" do
      expect_not_found(result)
      expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
    end
  end

  context "with an integration of another organization" do
    let(:integration) { create(:quickbooks_integration, organization: create(:organization)) }

    it "returns not found without asking Nango" do
      expect_not_found(result)
      expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
    end
  end

  context "without the quickbooks premium integration" do
    before { membership.organization.update!(premium_integrations: ["xero"]) }

    it "returns premium_integration_missing without asking Nango" do
      expect_graphql_error(result:, message: "premium_integration_missing")
      expect(result["errors"].first["extensions"]["status"]).to eq(403)
      expect(WebMock).not_to have_requested(:get, /api.nango.dev/)
    end
  end
end
