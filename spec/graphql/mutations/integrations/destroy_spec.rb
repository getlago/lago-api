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
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyIntegrationInput!) {
        destroyIntegration(input: $input) { id }
      }
    GQL
  end

  before { integration }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:delete"

  it "deletes an integration" do
    expect { result }.to change(::Integrations::BaseIntegration, :count).by(-1)
  end

  it "produces a security log" do
    result

    expect(security_logger).to have_received(:produce).with(
      organization: membership.organization,
      log_type: "integration",
      log_event: "integration.deleted",
      resources: {integration_name: integration.name, integration_type: "netsuite"}
    )
  end

  context "when okta integration", :premium do
    let(:integration) { create(:okta_integration, organization:) }

    before do
      organization.enable_okta_authentication!

      allow(::Integrations::Okta::DestroyService).to receive(:call).with(integration:).and_call_original
    end

    it "deletes calling the okta destroy service" do
      expect { result }.to change(::Integrations::BaseIntegration, :count).by(-1)
      expect(::Integrations::Okta::DestroyService).to have_received(:call).with(integration:)
    end

    it "produces a security log" do
      result

      expect(security_logger).to have_received(:produce).with(
        organization: membership.organization,
        log_type: "integration",
        log_event: "integration.deleted",
        resources: {integration_name: integration.name, integration_type: "okta"}
      )
    end
  end
end
