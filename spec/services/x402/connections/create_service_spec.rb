# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  include_context "with mocked security logger"

  let(:organization) { create(:organization) }
  let(:params) do
    {
      code: "cdp_main",
      name: "Coinbase CDP",
      networks: ["eip155:84532"],
      payout_addresses: {evm: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"},
      cdp_api_key_id: "key-id",
      cdp_api_key_secret: "key-secret"
    }
  end

  describe "#call" do
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
          payout_addresses: {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"}
        )
      end

      it "stores the secrets readable through the accessors" do
        expect(connection.reload).to have_attributes(cdp_api_key_id: "key-id", cdp_api_key_secret: "key-secret")
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
      let(:params) do
        {
          code: "cdp_main",
          name: "Coinbase CDP",
          networks: ["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
          payout_addresses: {evm: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"},
          cdp_api_key_id: "key-id",
          cdp_api_key_secret: "key-secret"
        }
      end

      it "fails with the validation errors" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({payout_addresses: ["missing_svm_payout_address"]})
      end

      it "persists nothing" do
        expect { result }.not_to change(X402::Connection, :count)
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end
  end
end
