# frozen_string_literal: true

require "rails_helper"

describe X402::Cdp::AccountsClient do
  subject(:lookup) { client.lookup(family:, address:) }

  include_context "with CDP credentials"

  let(:client) { described_class.new(api_key_id: cdp_api_key_id, api_key_secret: cdp_api_key_secret) }
  let(:family) { :evm }
  let(:address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:status) { 200 }
  let(:body) { {address:, name: "payout"}.to_json }

  before do
    allow(Rails.logger).to receive(:warn)
    stub_cdp_account(family, address, status:, body:)
  end

  def jwt_claims(request)
    token = request.headers["Authorization"].delete_prefix("Bearer ")
    JSON.parse(Base64.urlsafe_decode64(token.split(".")[1]))
  end

  it "finds the account" do
    expect(lookup).to have_attributes(family: :evm, outcome: :found, http_status: 200)
  end

  it "signs a token bound to the lookup" do
    lookup

    expect(a_request(:get, cdp_account_url(:evm, address)).with { |request| jwt_claims(request)["uri"] == "GET api.cdp.coinbase.com/platform/v2/evm/accounts/#{address}" })
      .to have_been_made.once
  end

  context "with a Solana address" do
    let(:family) { :svm }
    let(:address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }

    it "looks it up on the Solana endpoint" do
      expect(lookup).to have_attributes(family: :svm, outcome: :found)
    end
  end

  context "when CDP answers 404" do
    let(:status) { 404 }
    let(:body) { {errorType: "not_found", errorMessage: "EVM account with given address not found.", correlationId: "corr-404"}.to_json }

    it "is not found" do
      expect(lookup).to have_attributes(outcome: :not_found, http_status: 404, error_type: "not_found", correlation_id: "corr-404")
    end

    it "logs CDP's correlation id" do
      lookup
      expect(Rails.logger).to have_received(:warn).with(include("family=evm", "status=404", "correlation_id=corr-404"))
    end
  end

  context "when CDP answers 404 without its not_found error" do
    let(:status) { 404 }
    let(:body) { "<html>Not Found</html>" }

    it "is unavailable" do
      expect(lookup).to have_attributes(outcome: :unavailable, http_status: 404)
    end
  end

  context "when CDP answers 400" do
    let(:status) { 400 }
    let(:body) { {errorType: "invalid_request", correlationId: "corr-400"}.to_json }

    it "is invalid" do
      expect(lookup).to have_attributes(outcome: :invalid, error_type: "invalid_request")
    end
  end

  context "when CDP answers 400 without its invalid_request error" do
    let(:status) { 400 }
    let(:body) { {errorType: "malformed_token"}.to_json }

    it "is unavailable" do
      expect(lookup).to have_attributes(outcome: :unavailable, http_status: 400)
    end
  end

  context "when CDP answers 401 in plain text" do
    let(:status) { 401 }
    let(:body) { "Unauthorized\n" }

    it "is forbidden" do
      expect(lookup).to have_attributes(outcome: :forbidden, http_status: 401, error_type: nil)
    end
  end

  context "when CDP answers 403" do
    let(:status) { 403 }
    let(:body) { {errorType: "forbidden", correlationId: "corr-403"}.to_json }

    it "is forbidden" do
      expect(lookup).to have_attributes(outcome: :forbidden, http_status: 403)
    end
  end

  context "when CDP answers 429" do
    let(:status) { 429 }
    let(:body) { {errorType: "rate_limit_exceeded"}.to_json }

    it "is rate limited" do
      expect(lookup).to have_attributes(outcome: :rate_limited, http_status: 429)
    end
  end

  context "when CDP answers 503" do
    let(:status) { 503 }
    let(:body) { "" }

    it "is unavailable" do
      expect(lookup).to have_attributes(outcome: :unavailable, http_status: 503)
    end
  end

  context "when CDP answers 200 with a page that is not JSON" do
    let(:body) { "<html></html>" }

    it "is unavailable" do
      expect(lookup).to have_attributes(outcome: :unavailable, http_status: 200)
    end
  end

  context "when CDP does not answer" do
    before { stub_request(:get, cdp_account_url(family, address)).to_raise(Net::ReadTimeout) }

    it "is unavailable" do
      expect(lookup).to have_attributes(outcome: :unavailable, http_status: nil)
    end

    it "logs the transport error" do
      lookup
      expect(Rails.logger).to have_received(:warn).with(include("reason=no_response", "error=Net::ReadTimeout"))
    end
  end

  context "with an unusable secret" do
    let(:cdp_api_key_secret) { "key-secret" }

    it "raises before any request" do
      expect { lookup }.to raise_error(X402::Cdp::Jwt::InvalidKeyError)
      expect(a_request(:get, cdp_account_url(family, address))).not_to have_been_made
    end
  end
end
