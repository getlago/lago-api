# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::SyncService do
  subject(:sync_service) { described_class.new(integration:) }

  let(:integration) { create(:netsuite_integration) }

  describe ".call" do
    let(:lago_client) { instance_double(LagoHttpClient::Client) }
    let(:sync_endpoint) { "https://api.nango.dev/sync/trigger" }
    let(:syncs_list) do
      %w[
        netsuite-subsidiaries-sync
      ]
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new)
        .with(sync_endpoint, retries_on: [OpenSSL::SSL::SSLError])
        .and_return(lago_client)
      allow(lago_client).to receive(:post_with_response)
    end

    it "successfully calls sync endpoint" do
      sync_service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with(sync_endpoint, retries_on: [OpenSSL::SSL::SSLError])
      expect(lago_client).to have_received(:post_with_response) do |payload|
        expect(payload[:provider_config_key]).to eq("netsuite-tba")
        expect(payload[:syncs]).to eq(syncs_list)
      end
    end

    context "with a xero integration" do
      let(:integration) { create(:xero_integration) }

      it "triggers the xero syncs" do
        sync_service.call

        expect(lago_client).to have_received(:post_with_response) do |payload|
          expect(payload[:provider_config_key]).to eq("xero")
          expect(payload[:syncs]).to eq(%w[xero-accounts-sync xero-items-sync xero-contacts-sync])
        end
      end
    end

    context "with a quickbooks integration" do
      let(:integration) { create(:quickbooks_integration) }

      it "triggers the quickbooks catalog syncs" do
        sync_service.call

        expect(lago_client).to have_received(:post_with_response) do |payload|
          expect(payload[:provider_config_key]).to eq("quickbooks")
          expect(payload[:syncs]).to eq(%w[accounts items customers])
        end
      end

      context "when the integration is a sandbox" do
        let(:integration) do
          create(
            :quickbooks_integration,
            settings: {
              realm_id: "1234567890",
              sandbox: true,
              sync_invoices: false,
              sync_credit_notes: false,
              sync_payments: false
            }
          )
        end

        it "triggers the quickbooks catalog syncs on the sandbox provider config" do
          sync_service.call

          expect(lago_client).to have_received(:post_with_response) do |payload|
            expect(payload[:provider_config_key]).to eq("quickbooks-sandbox")
            expect(payload[:syncs]).to eq(%w[accounts items customers])
          end
        end
      end

      context "with only_items option" do
        subject(:sync_service) { described_class.new(integration:, options: {only_items: true}) }

        it "triggers the items sync only" do
          sync_service.call

          expect(lago_client).to have_received(:post_with_response) do |payload|
            expect(payload[:syncs]).to eq(["items"])
          end
        end
      end

      context "with only_accounts option" do
        subject(:sync_service) { described_class.new(integration:, options: {only_accounts: true}) }

        it "triggers the accounts sync only" do
          sync_service.call

          expect(lago_client).to have_received(:post_with_response) do |payload|
            expect(payload[:syncs]).to eq(["accounts"])
          end
        end
      end

      context "with only_customers option" do
        subject(:sync_service) { described_class.new(integration:, options: {only_customers: true}) }

        it "triggers the customers sync only" do
          sync_service.call

          expect(lago_client).to have_received(:post_with_response) do |payload|
            expect(payload[:syncs]).to eq(["customers"])
          end
        end
      end
    end
  end
end
