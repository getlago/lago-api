# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  include_context "with mocked security logger"
  include_context "with CDP credentials"

  let(:organization) { create(:organization) }
  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:params) do
    {
      code: "cdp_main",
      name: "Coinbase CDP",
      networks: ["eip155:84532"],
      payout_addresses: {evm: evm_address},
      cdp_api_key_id:,
      cdp_api_key_secret:
    }
  end

  describe "#call" do
    before do
      stub_cdp_supported
      stub_cdp_account(:evm, evm_address)
    end

    context "with valid params" do
      let(:connection) { result.connection }

      it "persists the connection with the given attributes" do
        expect(result).to be_success
        expect(connection).to be_persisted
        expect(connection).to have_attributes(
          organization:,
          code: "cdp_main",
          name: "Coinbase CDP",
          networks: ["eip155:84532"],
          payout_addresses: {"evm" => evm_address}
        )
      end

      it "stores the secrets readable through the accessors" do
        expect(connection.reload).to have_attributes(cdp_api_key_id:, cdp_api_key_secret:)
      end

      it "applies the defaults" do
        expect(connection).to have_attributes(facilitator: "coinbase_cdp", asset: "usdc", auto_create_customers: true)
      end

      it "produces a security log" do
        result

        expect(security_logger).to have_received(:produce).with(
          organization:,
          log_type: "integration",
          log_event: "integration.created",
          resources: {integration_name: "Coinbase CDP", integration_type: "x402"}
        )
      end
    end

    context "with an invalid connection" do
      let(:params) { super().merge(networks: ["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]) }

      it "fails with the validation errors" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({payout_addresses: ["missing_svm_payout_address"]})
      end

      it "persists nothing" do
        expect { result }.not_to change(X402::Connection, :count)
      end

      it "calls CDP for nothing" do
        result
        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end

    context "when the payout address is not in the key's CDP project" do
      before { stub_cdp_account(:evm, evm_address, status: 404) }

      it "fails with the address error" do
        expect(result.error.messages).to eq(payout_addresses: ["evm_not_in_cdp_project"])
      end

      it "persists nothing" do
        expect { result }.not_to change(X402::Connection, :count)
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end

    context "when CDP is unavailable" do
      before { stub_cdp_supported(status: 503, body: "") }

      it "fails with a third-party error" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end

      it "persists nothing" do
        expect { result }.not_to change(X402::Connection, :count)
      end
    end

    context "when another create takes the code during the CDP checks" do
      before do
        stub_request(:get, cdp_account_url(:evm, evm_address))
          .to_return { |_request|
            create(:x402_connection, organization:, code: "cdp_main")
            {status: 200, body: {address: evm_address}.to_json}
          }
          .then.to_return(status: 200, body: {address: evm_address}.to_json)
      end

      it "fails on code" do
        expect(result.error.messages).to eq(code: ["value_already_exist"])
      end
    end
  end
end
