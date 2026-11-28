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

    it "sends no request to Nango" do
      destroy_service.call

      expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made
    end

    context "with a QuickBooks integration" do
      let(:integration) { create(:quickbooks_integration, organization:) }
      let(:connection_url) { "https://api.nango.dev/connection/quickbooks-test-connection?provider_config_key=quickbooks" }
      let(:nango_status) { 204 }

      before { stub_request(:delete, connection_url).to_return(status: nango_status) }

      it "destroys it and deletes its Nango connection" do
        result = destroy_service.call

        expect(result).to be_success
        expect(Integrations::BaseIntegration.exists?(integration.id)).to be(false)
        expect(WebMock).to have_requested(:delete, connection_url)
          .with(headers: {"Authorization" => "Bearer #{ENV["NANGO_SECRET_KEY"]}"}).once
      end

      it_behaves_like "produces a security log", "integration.deleted" do
        before { destroy_service.call }
      end

      context "when the connection was flagged as pointing at another company" do
        let(:integration) do
          create(:quickbooks_integration, organization:, settings: {realm_id: "1234567890", sandbox: false, realm_id_mismatch: true})
        end

        it "destroys it and still deletes its Nango connection" do
          result = destroy_service.call

          expect(result).to be_success
          expect(Integrations::BaseIntegration.exists?(integration.id)).to be(false)
          expect(WebMock).to have_requested(:delete, connection_url).once
        end
      end

      context "when Nango fails" do
        let(:nango_status) { 500 }

        it "still destroys the integration" do
          result = destroy_service.call

          expect(result).to be_success
          expect(Integrations::BaseIntegration.exists?(integration.id)).to be(false)
          expect(WebMock).to have_requested(:delete, connection_url).once
        end

        it_behaves_like "produces a security log", "integration.deleted" do
          before { destroy_service.call }
        end
      end

      it "does not delete the Nango connection when the surrounding transaction rolls back" do
        ActiveRecord::Base.transaction(requires_new: true) do
          destroy_service.call
          raise ActiveRecord::Rollback
        end

        expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made
        expect(Integrations::BaseIntegration.exists?(integration.id)).to be(true)
      end

      context "when another QuickBooks integration shares the connection" do
        before do
          create(
            :quickbooks_integration,
            organization: create(:organization),
            settings: {realm_id: "9876543210", sandbox: false, sync_invoices: false, sync_credit_notes: false, sync_payments: false}
          )
        end

        it "destroys it without deleting the Nango connection" do
          result = destroy_service.call

          expect(result).to be_success
          expect(Integrations::BaseIntegration.exists?(integration.id)).to be(false)
          expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made
        end
      end
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
          expect(a_request(:delete, /api\.nango\.dev/)).not_to have_been_made
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
