# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::UpdateService do
  subject(:result) { described_class.call(connection:, params:) }

  include_context "with mocked security logger"
  include_context "with CDP credentials"

  let(:organization) { create(:organization) }
  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:svm_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }
  let(:connection) do
    create(
      :x402_connection,
      organization:,
      networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
      payout_addresses: {
        "evm" => evm_address,
        "svm" => svm_address
      },
      cdp_api_key_id:,
      cdp_api_key_secret:
    )
  end
  let(:params) { {name: "Renamed"} }

  def signed_by?(request, key)
    signing_input, _, signature = request.headers["Authorization"].delete_prefix("Bearer ").rpartition(".")
    key.verify(nil, Base64.urlsafe_decode64(signature), signing_input)
  end

  describe "#call" do
    before do
      stub_cdp_supported
      stub_cdp_account(:evm, evm_address)
      stub_cdp_account(:svm, svm_address)
    end

    context "when only name is sent" do
      it "changes the name and keeps the rest" do
        expect(result).to be_success
        expect(connection.reload).to have_attributes(
          name: "Renamed",
          networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
          payout_addresses: {
            "evm" => evm_address,
            "svm" => svm_address
          },
          cdp_api_key_id:,
          cdp_api_key_secret:
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

      it "calls CDP for nothing" do
        result
        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end

      context "when CDP is down" do
        before { stub_cdp_supported(status: 503, body: "") }

        it "succeeds" do
          expect(result).to be_success
        end
      end
    end

    context "when only cdp_api_key_secret is sent" do
      let(:rotated_signing_key) { OpenSSL::PKey.generate_key("ED25519") }
      let(:rotated_secret) { Base64.strict_encode64(rotated_signing_key.raw_private_key + rotated_signing_key.raw_public_key) }
      let(:params) { {cdp_api_key_secret: rotated_secret} }

      it "changes the secret and keeps the key id" do
        expect(result).to be_success
        expect(connection.reload).to have_attributes(cdp_api_key_id:, cdp_api_key_secret: rotated_secret)
      end

      it "checks the credentials with the new key" do
        result
        expect(a_request(:get, "#{cdp_host}/platform/v2/x402/supported").with { |request| signed_by?(request, rotated_signing_key) }).to have_been_made.once
      end

      it "verifies the addresses with the new key" do
        result
        expect(a_request(:get, cdp_account_url(:evm, evm_address)).with { |request| signed_by?(request, rotated_signing_key) }).to have_been_made.once
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

      context "when the addresses are not in the new key's CDP project" do
        before { stub_cdp_account(:evm, evm_address, status: 404) }

        it "fails with the address error" do
          expect(result.error.messages).to eq(payout_addresses: {evm: ["not_in_cdp_project"]})
        end

        it "keeps the previous secret" do
          result
          expect(connection.reload.cdp_api_key_secret).to eq(cdp_api_key_secret)
        end
      end
    end

    context "when the stored secret is sent again" do
      let(:params) { {cdp_api_key_secret:} }

      it "calls CDP for nothing" do
        expect(result).to be_success
        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end
    end

    context "when the stored EVM address is sent in lowercase" do
      let(:params) { {payout_addresses: {evm: evm_address.downcase, svm: svm_address}} }

      it "calls CDP for nothing" do
        expect(result).to be_success
        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end
    end

    context "when a Solana network is added" do
      let(:connection) do
        create(:x402_connection, organization:, networks: ["eip155:84532"], payout_addresses: {"evm" => evm_address, "svm" => svm_address}, cdp_api_key_id:, cdp_api_key_secret:)
      end
      let(:params) { {networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]} }

      it "verifies the Solana address" do
        result
        expect(a_request(:get, cdp_account_url(:svm, svm_address))).to have_been_made.once
      end

      context "when the Solana address is not in the key's CDP project" do
        before { stub_cdp_account(:svm, svm_address, status: 404) }

        it "fails with the address error" do
          expect(result.error.messages).to eq(payout_addresses: {svm: ["not_in_cdp_project"]})
        end

        it "keeps the connection EVM-only" do
          result
          expect(connection.reload.networks).to eq(["eip155:84532"])
        end
      end
    end

    context "when payout_addresses is sent" do
      let(:params) { {networks: ["eip155:84532"], payout_addresses: {evm: evm_address}} }

      it "replaces the stored hash" do
        expect(result).to be_success
        expect(connection.reload.payout_addresses).to eq({"evm" => evm_address})
      end

      it "verifies the EVM address" do
        result
        expect(a_request(:get, cdp_account_url(:evm, evm_address))).to have_been_made.once
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

      it "calls CDP for nothing" do
        result
        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
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

    context "when another update saved after the connection was loaded" do
      let(:connection) do
        create(
          :x402_connection,
          organization:,
          payout_addresses: {
            "evm" => evm_address,
            "svm" => svm_address
          },
          cdp_api_key_id:,
          cdp_api_key_secret:
        )
      end
      let(:params) { {networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]} }

      before do
        described_class.call(
          connection: X402::Connection.find(connection.id),
          params: {payout_addresses: {evm: evm_address}}
        )
      end

      it "validates against the saved connection" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(payout_addresses: {svm: ["value_is_mandatory"]})
      end

      it "keeps the saved networks" do
        result

        expect(connection.reload.networks).to eq(["eip155:84532"])
      end
    end

    context "when another update saves during the CDP checks" do
      let(:other_evm_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
      let(:connection) do
        create(:x402_connection, organization:, networks: ["eip155:84532"], payout_addresses: {"evm" => evm_address, "svm" => svm_address}, cdp_api_key_id:, cdp_api_key_secret:)
      end
      let(:params) { {networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]} }

      before do
        stub_cdp_account(:evm, other_evm_address)
        stub_request(:get, cdp_account_url(:svm, svm_address))
          .to_return { |_request|
            described_class.call(
              connection: X402::Connection.find(connection.id),
              params: {payout_addresses: {evm: other_evm_address, svm: svm_address}}
            )
            {status: 200, body: {address: svm_address}.to_json}
          }
          .then.to_return(status: 200, body: {address: svm_address}.to_json)
      end

      it "refuses to save what CDP did not verify" do
        expect(result.error.messages).to eq(base: ["changed_concurrently"])
      end

      it "keeps the other update" do
        result
        expect(connection.reload).to have_attributes(networks: ["eip155:84532"], payout_addresses: {"evm" => other_evm_address, "svm" => svm_address})
      end
    end

    context "when another update saved a checked field after the connection was loaded" do
      let(:other_evm_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
      let(:params) { {payout_addresses: {evm: evm_address, svm: svm_address}} }

      before do
        stub_cdp_account(:evm, other_evm_address)
        described_class.call(
          connection: X402::Connection.find(connection.id),
          params: {payout_addresses: {evm: other_evm_address, svm: svm_address}}
        )
      end

      it "refuses to save an unchecked change" do
        expect(result.error.messages).to eq(base: ["changed_concurrently"])
      end

      it "keeps the other update" do
        result
        expect(connection.reload.payout_addresses).to eq({"evm" => other_evm_address, "svm" => svm_address})
      end
    end

    context "when the connection is deleted during the CDP checks" do
      let(:params) { {networks: ["eip155:84532"], payout_addresses: {evm: evm_address}} }

      before do
        stub_request(:get, cdp_account_url(:evm, evm_address))
          .to_return { |_request|
            X402::Connections::DestroyService.call(connection: X402::Connection.find(connection.id))
            {status: 200, body: {address: evm_address}.to_json}
          }
          .then.to_return(status: 200, body: {address: evm_address}.to_json)
      end

      it "fails with a not found error" do
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end

      it "leaves the deleted connection unchanged" do
        result
        expect(X402::Connection.with_discarded.find(connection.id)).to have_attributes(
          discarded?: true,
          networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]
        )
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
