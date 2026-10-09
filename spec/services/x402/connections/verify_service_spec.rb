# frozen_string_literal: true

require "rails_helper"

describe X402::Connections::VerifyService do
  subject(:result) { described_class.call(connection:) }

  include_context "with CDP credentials"

  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:connection) do
    build(:x402_connection, networks: ["eip155:84532"], payout_addresses: {"evm" => evm_address}, cdp_api_key_id:, cdp_api_key_secret:)
  end

  before do
    allow(Rails.logger).to receive(:warn)
    stub_cdp_supported
    stub_cdp_account(:evm, evm_address)
  end

  it "succeeds" do
    expect(result).to be_success
  end

  it "checks the credentials on /supported" do
    result
    expect(a_request(:get, "#{cdp_host}/platform/v2/x402/supported")).to have_been_made.once
  end

  it "looks up the payout address" do
    result
    expect(a_request(:get, cdp_account_url(:evm, evm_address))).to have_been_made.once
  end

  {401 => "Unauthorized", 403 => {errorType: "forbidden"}.to_json}.each do |status, body|
    context "when CDP answers #{status} to /supported" do
      before { stub_cdp_supported(status:, body:) }

      it "fails on cdp_api_key" do
        expect(result.error.messages).to eq(cdp_api_key: ["invalid_credentials"])
      end

      it "makes no account lookup" do
        result
        expect(a_request(:get, cdp_account_url(:evm, evm_address))).not_to have_been_made
      end
    end
  end

  context "when the CDP account has no payment method" do
    before { stub_cdp_supported(status: 402, body: {errorType: "payment_method_required"}.to_json) }

    it "fails on cdp_api_key naming the payment method" do
      expect(result.error.messages).to eq(cdp_api_key: ["payment_method_required"])
    end
  end

  context "with an unusable secret" do
    let(:cdp_api_key_secret) { "key-secret" }

    it "fails on cdp_api_key" do
      expect(result.error.messages).to eq(cdp_api_key: ["invalid_credentials"])
    end

    it "calls CDP for nothing" do
      result
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end
  end

  context "when CDP is unavailable" do
    before { stub_cdp_supported(status: 503, body: "") }

    it "fails with a third-party error" do
      expect(result.error).to have_attributes(third_party: "coinbase_cdp", error_code: "unavailable_error")
    end

    it "makes no account lookup" do
      result
      expect(a_request(:get, cdp_account_url(:evm, evm_address))).not_to have_been_made
    end
  end

  context "when CDP rate limits /supported" do
    before { stub_cdp_supported(status: 429, body: "") }

    it "fails with a third-party error" do
      expect(result.error).to have_attributes(third_party: "coinbase_cdp", error_code: "rate_limit_error")
    end
  end

  context "with a network CDP does not list" do
    let(:svm_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }
    let(:connection) do
      build(:x402_connection, networks: ["solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"], payout_addresses: {"svm" => svm_address}, cdp_api_key_id:, cdp_api_key_secret:)
    end

    it "fails on networks" do
      expect(result.error.messages).to eq(networks: ["unsupported_network"])
    end

    it "makes no account lookup" do
      result
      expect(a_request(:get, cdp_account_url(:svm, svm_address))).not_to have_been_made
    end
  end

  context "when the payout address is not in the key's CDP project" do
    before { stub_cdp_account(:evm, evm_address, status: 404) }

    it "fails on payout_addresses" do
      expect(result.error.messages).to eq(payout_addresses: ["evm_not_in_cdp_project"])
    end
  end
end
