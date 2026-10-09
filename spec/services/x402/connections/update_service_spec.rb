# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::UpdateService do
  subject(:result) { described_class.call(connection:, params:) }

  include_context "with mocked security logger"

  let(:organization) { create(:organization) }
  let(:connection) do
    create(
      :x402_connection,
      organization:,
      networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
      payout_addresses: {
        "evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "svm" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4"
      }
    )
  end
  let(:params) { {name: "Renamed"} }

  describe "#call" do
    context "when only name is sent" do
      it "changes the name and keeps the rest" do
        expect(result).to be_success
        expect(connection.reload).to have_attributes(
          name: "Renamed",
          networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
          payout_addresses: {
            "evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
            "svm" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4"
          },
          cdp_api_key_id: "test-key-id",
          cdp_api_key_secret: "test-key-secret"
        )
      end

      it "produces a security log with the diff" do
        result

        expect(security_logger).to have_received(:produce).with(
          organization:,
          log_type: "integration",
          log_event: "integration.updated",
          resources: {integration_name: "Renamed", integration_type: "x402", name: {deleted: "Coinbase CDP", added: "Renamed"}}
        )
      end
    end

    context "when only cdp_api_key_secret is sent" do
      let(:params) { {cdp_api_key_secret: "rotated-secret"} }

      it "changes the secret and keeps the key id" do
        expect(result).to be_success
        expect(connection.reload).to have_attributes(cdp_api_key_id: "test-key-id", cdp_api_key_secret: "rotated-secret")
      end

      it "produces a security log without the secrets" do
        result

        expect(security_logger).to have_received(:produce).with(
          organization:,
          log_type: "integration",
          log_event: "integration.updated",
          resources: {integration_name: "Coinbase CDP", integration_type: "x402"}
        )
      end
    end

    context "when payout_addresses is sent" do
      let(:params) { {networks: ["eip155:84532"], payout_addresses: {evm: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"}} }

      it "replaces the stored hash" do
        expect(result).to be_success
        expect(connection.reload.payout_addresses).to eq({"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"})
      end
    end

    context "when create-only fields are sent" do
      let(:params) { {facilitator: "coinbase_cdp", asset: "eurc"} }

      it "ignores them" do
        expect(result).to be_success
        expect(connection.reload).to have_attributes(facilitator: "coinbase_cdp", asset: "usdc")
      end
    end

    context "when the update is invalid" do
      let(:params) { {name: "Renamed", networks: ["eip155:84532", "eip155:8453"]} }

      it "fails with the validation errors" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({networks: ["mixed_environments"]})
      end

      it "changes nothing" do
        result

        expect(connection.reload).to have_attributes(
          name: "Coinbase CDP",
          networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]
        )
      end

      it_behaves_like "does not produce a security log" do
        before { result }
      end
    end

    context "without a connection" do
      let(:connection) { nil }

      it "fails with a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("x402_connection_not_found")
      end
    end
  end
end
