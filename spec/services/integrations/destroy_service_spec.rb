# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::DestroyService do
  subject(:destroy_service) { described_class.new(integration:) }

  include_context "with mocked security logger"

  let_it_be(:membership) { create(:membership) }
  let_it_be(:membership) { create(:membership) }
  let_it_be(:organization) { create_default(:organization) }
  let(:integration) { create(:netsuite_integration, organization:) }

  describe ".call" do
    before { integration }

    it "destroys the integration" do
      expect { destroy_service.call }
        .to change(Integrations::BaseIntegration, :count).by(-1)
    end

    it_behaves_like "produces a security log", "integration.deleted" do
      before { destroy_service.call }
    end

    context "with an agent storefront" do
      let(:integration) { create(:agent_storefront_integration, organization:) }
      let(:registration) { create(:agent_registration, storefront: integration) }

      it "destroys it while no agent is enrolled" do
        registration

        expect { destroy_service.call }.to change(Integrations::BaseIntegration, :count).by(-1)
      end

      context "when an agent is enrolled" do
        before { create(:subscription, organization:, external_id: Agents::ExternalIds.subscription(registration)) }

        it "refuses and keeps it" do
          result = destroy_service.call

          expect(result.error.code).to eq("agent_storefront_has_enrolled_agents")
          expect(integration.reload).to be_present
        end
      end
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
