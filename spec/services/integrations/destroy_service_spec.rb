# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::DestroyService do
  subject(:destroy_service) { described_class.new(integration:) }

  include_context "with mocked security logger"

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }

  describe ".call" do
    before { integration }

    it "destroys the integration" do
      expect { destroy_service.call }
        .to change(Integrations::BaseIntegration, :count).by(-1)
    end

    it "produces a security log" do
      destroy_service.call

      expect(security_logger).to have_received(:produce).with(
        organization:,
        log_type: "integration",
        log_event: "integration.deleted",
        resources: {integration_name: integration.name, integration_type: "netsuite"}
      )
    end

    context "when integration is not found" do
      let(:integration) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("integration_not_found")
      end
    end
  end
end
