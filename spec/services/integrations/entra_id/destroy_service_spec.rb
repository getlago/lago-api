# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::EntraId::DestroyService do
  subject(:destroy_service) { described_class.new(integration:) }

  include_context "with mocked security logger"

  let_it_be(:membership, refind: true) { create(:membership) }
  let_it_be(:membership, refind: true) { create(:membership) }
  let_it_be(:organization, refind: true) { create_default(:organization) }
  let(:integration) { create(:entra_id_integration, organization:) }

  describe ".call", :premium do
    before do
      integration
      organization.update!(premium_integrations: ["entra_id"])
      organization.enable_entra_id_authentication!
    end

    it "destroys the integration" do
      expect { destroy_service.call }
        .to change(Integrations::BaseIntegration, :count).by(-1)
    end

    it "removes the authentication_method" do
      destroy_service.call
      expect(organization.authentication_methods).not_to include("entra_id")
    end

    it_behaves_like "produces a security log", "integration.deleted" do
      before { destroy_service.call }
    end

    context "when integration is not found" do
      let(:integration) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("integration_not_found")
      end
    end

    context "when destroy is not allowed" do
      before do
        organization.update!(authentication_methods: ["entra_id"])
      end

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("enabled_authentication_methods_required")
      end
    end

    context "when another change left Entra ID as the only login method meanwhile" do
      before do
        organization.update!(premium_integrations: ["entra_id"], authentication_methods: %w[email_password entra_id])
        Organization.find(organization.id).update!(authentication_methods: ["entra_id"])
      end

      it "reads the methods under the lock and refuses" do
        result = destroy_service.call

        expect(result.error.code).to eq("enabled_authentication_methods_required")
        expect(Integrations::BaseIntegration.exists?(integration.id)).to be(true)
      end
    end

    context "when the organization has a sandbox" do
      let(:sandbox) { create(:organization, :sandbox, production_organization: organization) }

      before do
        organization.update!(premium_integrations: ["entra_id"], authentication_methods: %w[email_password entra_id])
        sandbox
        Organizations::SyncSandboxSettingsService.call!(organization:)
      end

      it "removes the Entra ID login method from the sandbox too" do
        expect(sandbox.reload.authentication_methods).to include("entra_id")

        expect(destroy_service.call).to be_success
        expect(sandbox.reload.authentication_methods).to eq(["email_password"])
      end
    end

    context "when the organization is a sandbox" do
      let(:sandbox) { create(:organization, :sandbox, premium_integrations: ["entra_id"], authentication_methods: %w[email_password entra_id]) }
      let(:integration) { create(:entra_id_integration, organization: sandbox) }

      it "refuses to destroy the integration" do
        result = destroy_service.call

        expect(result.error.code).to eq("sandbox_managed_by_production")
        expect(Integrations::BaseIntegration.exists?(integration.id)).to be(true)
        expect(sandbox.reload.authentication_methods).to eq(%w[email_password entra_id])
      end
    end

    context "when entra_id authentication is disabled" do
      before do
        organization.update(authentication_methods: ["email_password"])
      end

      it "destroys the integration" do
        expect { destroy_service.call }
          .to change(Integrations::BaseIntegration, :count).by(-1)
      end
    end
  end
end
