# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::VerifyPayoutAddressService do
  subject(:result) { described_class.call(connection:) }

  include_context "with CDP credentials"

  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:svm_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }
  let(:networks) { ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"] }
  let(:connection) do
    build(:x402_connection, networks:, payout_addresses: {"evm" => evm_address, "svm" => svm_address}, cdp_api_key_id:, cdp_api_key_secret:)
  end
  let(:evm_status) { 200 }
  let(:svm_status) { 200 }

  before do
    allow(Rails.logger).to receive(:warn)
    stub_cdp_account(:evm, evm_address, status: evm_status)
    stub_cdp_account(:svm, svm_address, status: svm_status)
  end

  context "when every in-use address is a CDP account" do
    it "succeeds" do
      expect(result).to be_success
    end

    it "looks up the EVM address once" do
      result
      expect(a_request(:get, cdp_account_url(:evm, evm_address))).to have_been_made.once
    end

    it "looks up the Solana address once" do
      result
      expect(a_request(:get, cdp_account_url(:svm, svm_address))).to have_been_made.once
    end
  end

  context "with a family no network uses" do
    let(:networks) { ["eip155:84532"] }

    it "leaves its address unverified" do
      result
      expect(a_request(:get, cdp_account_url(:svm, svm_address))).not_to have_been_made
    end
  end

  context "when an address is not in the key's CDP project" do
    let(:evm_status) { 404 }

    it "fails on payout_addresses naming the family" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(payout_addresses: {evm: ["not_in_cdp_project"]})
    end
  end

  context "when no address is in the key's CDP project" do
    let(:evm_status) { 404 }
    let(:svm_status) { 404 }

    it "reports every family in one failure" do
      expect(result.error.messages).to eq(payout_addresses: {evm: ["not_in_cdp_project"], svm: ["not_in_cdp_project"]})
    end
  end

  context "when CDP rejects an address the local check accepted" do
    let(:svm_status) { 400 }

    it "fails on payout_addresses" do
      expect(result.error.messages).to eq(payout_addresses: {svm: ["rejected_by_cdp"]})
    end
  end

  [401, 403].each do |status|
    context "when CDP answers #{status} to a lookup" do
      let(:evm_status) { status }

      it "fails with the missing account-read permission" do
        expect(result.error.messages).to eq(cdp_api_key: ["missing_account_read_permission"])
      end

      it "stops before the next lookup" do
        result
        expect(a_request(:get, cdp_account_url(:svm, svm_address))).not_to have_been_made
      end
    end
  end

  context "when CDP is unavailable" do
    let(:evm_status) { 503 }

    it "fails with a third-party error" do
      expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      expect(result.error).to have_attributes(third_party: "coinbase_cdp", error_code: "unavailable_error")
    end

    it "stops before the next lookup" do
      result
      expect(a_request(:get, cdp_account_url(:svm, svm_address))).not_to have_been_made
    end
  end

  context "when CDP does not answer" do
    before { stub_request(:get, cdp_account_url(:evm, evm_address)).to_raise(Net::ReadTimeout) }

    it "fails with a third-party error" do
      expect(result.error).to have_attributes(third_party: "coinbase_cdp", error_code: "unavailable_error")
    end

    it "stops before the next lookup" do
      result
      expect(a_request(:get, cdp_account_url(:svm, svm_address))).not_to have_been_made
    end
  end

  context "when CDP rate limits a lookup" do
    let(:evm_status) { 429 }

    it "fails with a third-party error" do
      expect(result.error).to have_attributes(third_party: "coinbase_cdp", error_code: "rate_limit_error")
    end
  end

  context "when the EVM address is not in the key's CDP project" do
    let(:evm_status) { 404 }

    context "with the Solana lookup unavailable" do
      let(:svm_status) { 503 }

      it "fails closed with a third-party error" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
      end
    end
  end
end
