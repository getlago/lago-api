# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Okta::DestroyService do
  subject(:destroy_service) { described_class.new(integration:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:okta_integration, organization:) }

  describe ".call" do
    around { |test| lago_premium!(&test) }

    before do
      integration
      organization.enable_okta_authentication!
    end

    it "destroys the integration" do
      expect { destroy_service.call }
        .to change(Integrations::BaseIntegration, :count).by(-1)
    end

    it "removes the authentication_method" do
      destroy_service.call
      expect(organization.authentication_methods).not_to include("okta")
    end

    context "when integration is not found" do
      let(:integration) { nil }

      it "returns an error" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq("integration_not_found")
        end
      end
    end

    context "when destroy is not allowed" do
      before do
        organization.update!(authentication_methods: ["okta"])
      end

      it "returns an error" do
        result = destroy_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq("enabled_authentication_methods_required")
        end
      end
    end

    context "when okta authentication is disabled" do
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
