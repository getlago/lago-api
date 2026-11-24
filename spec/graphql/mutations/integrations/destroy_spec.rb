# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Integrations::Destroy do
  subject(:result) do
    execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: integration.id}}
    )
  end

  include_context "with mocked security logger"

  let(:required_permission) { "organization:integrations:delete" }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:mutation) do
    <<-GQL
      mutation($input: DestroyIntegrationInput!) {
        destroyIntegration(input: $input) { id }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let_it_be(:membership) { create_default(:membership) }

  before { integration }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:delete"

  it "deletes an integration" do
    expect { result }.to change(::Integrations::BaseIntegration, :count).by(-1)
  end

  it_behaves_like "produces a security log", "integration.deleted" do
    before { result }
  end

  context "when agent storefront integration" do
    let(:integration) { create(:agent_storefront_integration, organization:) }

    it "deletes the integration" do
      expect { result }.to change(::Integrations::BaseIntegration, :count).by(-1)
    end

    it_behaves_like "produces a security log", "integration.deleted" do
      before { result }
    end
  end

  context "when okta integration", :premium do
    let(:required_permission) { %w[organization:integrations:delete authentication_methods:update] }
    let(:integration) { create(:okta_integration, organization:) }

    before do
      organization.enable_okta_authentication!

      allow(::Integrations::Okta::DestroyService).to receive(:call).with(integration:).and_call_original
    end

    it "deletes calling the okta destroy service" do
      expect { result }.to change(::Integrations::BaseIntegration, :count).by(-1)
      expect(::Integrations::Okta::DestroyService).to have_received(:call).with(integration:)
    end

    it_behaves_like "produces a security log", "integration.deleted" do
      before { result }
    end

    context "without the authentication methods permission" do
      let(:required_permission) { "organization:integrations:delete" }

      it "does not delete the integration" do
        expect { result }.not_to change(::Integrations::BaseIntegration, :count)
        expect_forbidden_error(result)
      end
    end
  end

  context "when entra id integration without the authentication methods permission", :premium do
    let(:integration) { create(:entra_id_integration, organization:) }

    it "does not delete the integration" do
      expect { result }.not_to change(::Integrations::BaseIntegration, :count)
      expect_forbidden_error(result)
    end
  end

  context "with a QuickBooks integration" do
    let(:integration) { create(:quickbooks_integration, organization:) }
    let(:connection_url) { "https://api.nango.dev/connection/quickbooks-test-connection?provider_config_key=quickbooks" }

    before { stub_request(:delete, connection_url).to_return(status: 204) }

    it "deletes the QuickBooks integration and its Nango connection" do
      expect { result }.to change(::Integrations::QuickbooksIntegration, :count).by(-1)
      expect(result["data"]["destroyIntegration"]["id"]).to eq(integration.id)
      expect(WebMock).to have_requested(:delete, connection_url).once
    end

    context "when the QuickBooks integration belongs to another organization" do
      let(:integration) { create(:quickbooks_integration, organization: create(:organization)) }

      it "does not delete the QuickBooks integration" do
        expect { result }.not_to change(::Integrations::QuickbooksIntegration, :count)
        expect_not_found(result)
        expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made
      end
    end
  end
end
