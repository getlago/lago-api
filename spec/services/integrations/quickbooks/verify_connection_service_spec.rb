# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Quickbooks::VerifyConnectionService, :premium do
  let_it_be(:organization, refind: true) { create_default(:organization) }

  describe "#call" do
    subject(:result) { described_class.call(integration:) }

    let(:integration) { create(:quickbooks_integration, organization:, settings:) }
    let(:stored_realm_id) { "1234567890" }
    let(:mismatch) { nil }
    let(:settings) do
      {
        realm_id: stored_realm_id,
        realm_id_mismatch: mismatch,
        sandbox: false,
        sync_invoices: false,
        sync_credit_notes: false,
        sync_payments: false
      }.compact
    end
    let(:connection_url) do
      "https://api.nango.dev/connection/quickbooks-test-connection?provider_config_key=quickbooks"
    end
    let(:nango_realm_id) { "1234567890" }
    let(:response_status) { 200 }
    let(:response_body) do
      {
        "connection_config" => {"realmId" => nango_realm_id},
        "credentials" => {"access_token" => "fake-access-token"}
      }.to_json
    end
    let(:log_output) { StringIO.new }

    before do
      organization.update!(premium_integrations: ["quickbooks"])
      allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(log_output))

      stub_request(:get, connection_url)
        .to_return(status: response_status, body: response_body, headers: {"Content-Type" => "application/json"})
    end

    shared_examples "a refused check before Nango" do |error_class, message_or_code|
      it "fails without asking Nango" do
        expect(result).not_to be_success
        expect(result.error).to be_a(error_class)

        if error_class == BaseService::NotFoundFailure
          expect(result.error.message).to eq(message_or_code)
        else
          expect(result.error.code).to eq(message_or_code)
        end

        expect(WebMock).not_to have_requested(:get, connection_url)
      end
    end

    shared_examples "a lookup failure that keeps the flag" do |error_code|
      [nil, true].each do |flag|
        context "when the flag is #{flag ? "set" : "unset"}" do
          let(:mismatch) { flag }

          it "passes the ConnectionService error through and leaves the flag as it was" do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ThirdPartyFailure)
            expect(result.error.third_party).to eq("Nango")
            expect(result.error.error_code).to eq(error_code)

            integration.reload
            expect(integration.realm_id_mismatch).to eq(flag)
            expect(integration.realm_id).to eq("1234567890")
            expect(log_output.string).not_to include("fake-access-token")
          end
        end
      end
    end

    context "when Nango returns the stored realm id" do
      it "returns the integration without writing it" do
        integration
        updated_at = integration.reload.updated_at

        expect(result).to be_success
        expect(result.integration).to eq(integration)

        integration.reload
        expect(integration.updated_at).to eq(updated_at)
        expect(integration.settings).not_to have_key("realm_id_mismatch")
        expect(integration.realm_id).to eq("1234567890")
        expect(WebMock).to have_requested(:get, connection_url).once
        expect(log_output.string).not_to include("fake-access-token")
      end

      context "when the integration is flagged" do
        let(:mismatch) { true }

        it "clears the flag and keeps the realm id" do
          expect(result).to be_success
          expect(result.integration).to eq(integration)

          integration.reload
          expect(integration.realm_id_mismatch?).to eq(false)
          expect(integration.realm_id).to eq("1234567890")
        end
      end
    end

    context "when Nango returns another realm id" do
      let(:nango_realm_id) { "9999999999" }

      it "refuses with realm_id_changed, flags the integration and keeps the stored realm id" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("realm_id_changed")

        integration.reload
        expect(integration.realm_id_mismatch?).to eq(true)
        expect(integration.realm_id).to eq("1234567890")
        expect(integration.connection_id).to eq("quickbooks-test-connection")
        expect(integration.sandbox?).to eq(false)
        expect(log_output.string).not_to include("fake-access-token")
        expect(log_output.string).not_to include("9999999999")
      end

      context "when a sync flag is saved during the Nango lookup" do
        before do
          allow(Integrations::Aggregator::ConnectionService).to receive(:call).and_wrap_original do |original, **args|
            Integrations::QuickbooksIntegration.find(integration.id).update!(sync_invoices: true)
            original.call(**args)
          end
        end

        it "flags the integration and keeps that sync flag" do
          expect(result.error.code).to eq("realm_id_changed")

          integration.reload
          expect(integration.realm_id_mismatch?).to eq(true)
          expect(integration.sync_invoices).to eq(true)
        end
      end

      context "when the integration is already flagged" do
        let(:mismatch) { true }

        it "still refuses and leaves the flag set without writing the integration" do
          integration
          updated_at = integration.reload.updated_at

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("realm_id_changed")

          integration.reload
          expect(integration.realm_id_mismatch?).to eq(true)
          expect(integration.updated_at).to eq(updated_at)
        end
      end
    end

    context "when the stored realm id is blank" do
      let(:stored_realm_id) { nil }

      it "refuses with realm_id_changed and flags the integration without storing the found realm" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("realm_id_changed")

        integration.reload
        expect(integration.realm_id_mismatch?).to eq(true)
        expect(integration.realm_id).to be_nil
      end
    end

    context "when Nango returns a 404" do
      let(:response_status) { 404 }
      let(:response_body) { {"error" => "fake-access-token not found"}.to_json }

      it_behaves_like "a lookup failure that keeps the flag", "connection_not_found"
    end

    context "when the connection has no realm id" do
      let(:response_body) { {"credentials" => {"access_token" => "fake-access-token"}}.to_json }

      it_behaves_like "a lookup failure that keeps the flag", "realm_id_missing"
    end

    context "when Nango returns a 500" do
      let(:response_status) { 500 }
      let(:response_body) { {"error" => "fake-access-token server error"}.to_json }

      it_behaves_like "a lookup failure that keeps the flag", "connection_lookup_failed"
    end

    context "when the request times out" do
      before { stub_request(:get, connection_url).to_timeout }

      it_behaves_like "a lookup failure that keeps the flag", "connection_lookup_failed"
    end

    context "when saving the flag fails validation" do
      let(:nango_realm_id) { "9999999999" }

      before do
        integration.update_column(:name, "") # rubocop:disable Rails/SkipsModelValidations
      end

      it "returns a record validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to have_key(:name)
      end
    end

    context "without an integration" do
      let(:integration) { nil }

      it_behaves_like "a refused check before Nango", BaseService::NotFoundFailure, "integration_not_found"
    end

    context "with a Xero integration" do
      let(:integration) { create(:xero_integration, organization:) }

      it_behaves_like "a refused check before Nango", BaseService::NotFoundFailure, "integration_not_found"
    end

    context "when the organization has no QuickBooks premium integration" do
      before { organization.update!(premium_integrations: []) }

      it_behaves_like "a refused check before Nango", BaseService::ForbiddenFailure, "premium_integration_missing"
    end
  end
end
