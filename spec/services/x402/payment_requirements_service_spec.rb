# frozen_string_literal: true

require "rails_helper"

describe X402::PaymentRequirementsService do
  subject(:result) { described_class.call(connection:, amount_cents: 1_000) }

  include_context "with an x402 payment"

  let(:evm_payout) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:svm_payout) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }
  let(:devnet) { "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" }
  let(:fee_payer) { "GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb" }
  let(:connection) { create(:x402_connection) }

  def supported_body(network, fee_payer)
    {kinds: [{x402Version: 2, scheme: "exact", network:, extra: {feePayer: fee_payer}}]}.to_json
  end

  context "with an EVM network" do
    it "builds an exact requirement carrying the EIP-712 domain" do
      expect(result.requirements).to eq([{
        scheme: "exact", network: "eip155:84532", asset: "usdc",
        asset_address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        extra: {"name" => "USDC", "version" => "2"},
        pay_to: evm_payout, amount_atomic: "10000000", max_timeout_seconds: 60
      }])
    end

    it "does not call the facilitator" do
      result
      expect(a_request(:get, "#{cdp_facilitator_url}/supported")).not_to have_been_made
    end
  end

  context "with a Solana network" do
    let(:connection) { create(:x402_connection, :solana, cdp_api_key_id:, cdp_api_key_secret:) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 200, body: supported_body(devnet, fee_payer)) }

    it "carries the fee payer read from /supported" do
      expect(result.requirements.sole).to include(
        network: devnet, asset_address: "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU",
        extra: {"feePayer" => fee_payer}, pay_to: svm_payout, amount_atomic: "10000000"
      )
    end
  end

  context "when the fee payer rotates between challenges" do
    let(:connection) { create(:x402_connection, :solana, cdp_api_key_id:, cdp_api_key_secret:) }
    let(:rotated) { "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG" }
    let(:fee_payers) { Array.new(2) { described_class.call(connection:, amount_cents: 1_000).requirements.sole[:extra]["feePayer"] } }

    before do
      stub_request(:get, "#{cdp_facilitator_url}/supported")
        .to_return({status: 200, body: supported_body(devnet, fee_payer)}, {status: 200, body: supported_body(devnet, rotated)})
    end

    it "reads it afresh for each challenge" do
      expect(fee_payers).to eq([fee_payer, rotated])
    end
  end

  context "with a mainnet connection offering both families" do
    let(:connection) do
      create(:x402_connection, networks: ["eip155:8453", "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"],
        payout_addresses: {"evm" => evm_payout, "svm" => svm_payout}, cdp_api_key_id:, cdp_api_key_secret:)
    end

    before do
      stub_request(:get, "#{cdp_facilitator_url}/supported")
        .to_return(status: 200, body: supported_body("solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", fee_payer))
    end

    it "resolves each network's asset" do
      expect(result.requirements.map { |entry| entry.slice(:network, :asset_address, :extra) }).to eq([
        {network: "eip155:8453", asset_address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", extra: {"name" => "USD Coin", "version" => "2"}},
        {network: "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp", asset_address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", extra: {"feePayer" => fee_payer}}
      ])
    end
  end

  context "when /supported rejects the credentials" do
    let(:connection) { create(:x402_connection, :solana, cdp_api_key_id:, cdp_api_key_secret:) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 401, body: {errorType: "unauthorized"}.to_json) }

    it "fails as a third-party error naming the reason" do
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      expect(result.error.error_message).to eq("credential_error: supported: HTTP 401")
    end
  end

  context "when /supported is unavailable" do
    let(:connection) { create(:x402_connection, :solana, cdp_api_key_id:, cdp_api_key_secret:) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 503, body: "{}") }

    it "fails as a third-party error" do
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
    end
  end

  context "when /supported lists no fee payer for the network" do
    let(:connection) { create(:x402_connection, :solana, cdp_api_key_id:, cdp_api_key_secret:) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 200, body: supported_body("eip155:84532", fee_payer)) }

    it "fails as a third-party error" do
      expect(result.error.error_message).to eq("unavailable_error: supported: no valid fee payer for #{devnet}")
    end
  end

  context "when the listed fee payer is not a Solana address" do
    let(:connection) { create(:x402_connection, :solana, cdp_api_key_id:, cdp_api_key_secret:) }

    before { stub_request(:get, "#{cdp_facilitator_url}/supported").to_return(status: 200, body: supported_body(devnet, "0xnotsolana")) }

    it "fails as a third-party error" do
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
    end
  end
end
