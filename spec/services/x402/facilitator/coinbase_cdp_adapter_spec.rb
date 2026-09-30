# frozen_string_literal: true

require "rails_helper"

describe X402::Facilitator::CoinbaseCdpAdapter do
  subject(:adapter) { described_class.new(api_key_id: cdp_api_key_id, api_key_secret: cdp_api_key_secret) }

  include_context "with an x402 payment"

  let(:payment) { x402_evm_payment }
  let(:payment_requirements) { x402_evm_requirements }
  let(:fault) { nil }

  before do
    allow(Rails.logger).to receive(:warn)
    stub_cdp_facilitator(fault:)
  end

  def jwt_claims(request)
    token = request.headers["Authorization"].delete_prefix("Bearer ")
    JSON.parse(Base64.urlsafe_decode64(token.split(".")[1]))
  end

  def stub_answer(path, status:, body:)
    stub_request((path == "supported") ? :get : :post, "#{cdp_facilitator_url}/#{path}").to_return(status:, body:)
  end

  describe "#verify" do
    subject(:verification) { adapter.verify(payment:, payment_requirements:) }

    it "is valid" do
      expect(verification).to have_attributes(valid?: true, payer: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2")
    end

    context "with a Bazaar extension" do
      let(:payment) { x402_evm_payment.merge("extensions" => {"bazaar" => {"info" => {"input" => {"method" => "GET"}}}}) }

      it "forwards the payment and its requirements unchanged" do
        verification

        expect(a_request(:post, "#{cdp_facilitator_url}/verify").with { |request| request.body == {x402Version: 2, paymentPayload: payment, paymentRequirements: payment_requirements}.to_json })
          .to have_been_made.once
      end
    end

    context "with a v1 payment" do
      let(:payment) { {"x402Version" => 1, "scheme" => "exact", "network" => "base-sepolia", "payload" => x402_evm_payment["payload"]} }

      it "speaks the payment's version" do
        verification

        expect(a_request(:post, "#{cdp_facilitator_url}/verify").with { |request| JSON.parse(request.body)["x402Version"] == 1 }).to have_been_made
      end
    end

    context "with symbol keys" do
      let(:payment) { x402_evm_payment.deep_symbolize_keys }

      it "forwards the payment as given" do
        verification

        expect(a_request(:post, "#{cdp_facilitator_url}/verify").with { |request| JSON.parse(request.body) == {"x402Version" => 2, "paymentPayload" => x402_evm_payment, "paymentRequirements" => payment_requirements} })
          .to have_been_made
      end
    end

    it "signs a token bound to the call" do
      verification

      expect(a_request(:post, "#{cdp_facilitator_url}/verify").with { |request| jwt_claims(request)["uri"] == "POST api.cdp.coinbase.com/platform/v2/x402/verify" }).to have_been_made
    end

    context "when CDP rejects the payment" do
      let(:fault) { :verify_reject }

      it "is invalid with CDP's reason" do
        expect(verification).to have_attributes(valid?: false, invalid_reason: "invalid_exact_evm_payload_signature")
      end

      it "logs the rejection" do
        verification

        expect(Rails.logger).to have_received(:warn)
          .with("X402::Facilitator::CoinbaseCdpAdapter call failed operation=verify reason=invalid_exact_evm_payload_signature status=200")
      end
    end

    context "when a Solana verify names no payer" do
      before { stub_answer("verify", status: 200, body: {isValid: true}.to_json) }

      it "has no payer" do
        expect(verification).to have_attributes(valid?: true, payer: nil)
      end
    end

    context "when CDP refuses the request" do
      before { stub_answer("verify", status: 400, body: {errorType: "invalid_request", errorMessage: "bad payload", correlationId: "corr-1"}.to_json) }

      it "is invalid with the error type" do
        expect(verification).to have_attributes(valid?: false, invalid_reason: "invalid_request")
      end
    end

    context "when CDP answers 401" do
      before { stub_answer("verify", status: 401, body: "Unauthorized") }

      it "raises a credential error" do
        expect { verification }.to raise_error(X402::Facilitator::CredentialError) { |error| expect(error.http_status).to eq(401) }
      end

      it "logs it" do
        expect { verification }.to raise_error(X402::Facilitator::CredentialError)
        expect(Rails.logger).to have_received(:warn).with("X402::Facilitator::CoinbaseCdpAdapter call failed operation=verify reason=unauthorized status=401")
      end
    end

    context "when CDP answers 402" do
      before { stub_answer("verify", status: 402, body: {errorType: "payment_method_required", correlationId: "corr-3"}.to_json) }

      it "raises a credential error" do
        expect { verification }.to raise_error(X402::Facilitator::CredentialError) { |error| expect(error.http_status).to eq(402) }
      end

      it "logs it" do
        expect { verification }.to raise_error(X402::Facilitator::CredentialError)
        expect(Rails.logger).to have_received(:warn).with("X402::Facilitator::CoinbaseCdpAdapter call failed operation=verify reason=payment_required status=402 error_type=payment_method_required correlation_id=corr-3")
      end
    end

    context "when CDP answers 403" do
      before { stub_answer("verify", status: 403, body: {errorType: "forbidden", correlationId: "corr-2"}.to_json) }

      it "raises a credential error" do
        expect { verification }.to raise_error(X402::Facilitator::CredentialError) { |error| expect(error.correlation_id).to eq("corr-2") }
      end
    end

    context "when screening declines the payment" do
      before { stub_answer("verify", status: 403, body: {errorType: "kyt_risk_detected", correlationId: "corr-4"}.to_json) }

      it "is invalid with the screening reason" do
        expect(verification).to have_attributes(valid?: false, invalid_reason: "kyt_risk_detected")
      end

      it "logs it" do
        verification

        expect(Rails.logger).to have_received(:warn).with("X402::Facilitator::CoinbaseCdpAdapter call failed operation=verify reason=kyt_risk_detected status=403 correlation_id=corr-4")
      end
    end

    context "when CDP answers 429" do
      before { stub_answer("verify", status: 429, body: {errorType: "rate_limit_exceeded"}.to_json) }

      it "raises a rate-limit error" do
        expect { verification }.to raise_error(X402::Facilitator::RateLimitError)
      end
    end

    context "when CDP answers 500" do
      before { stub_answer("verify", status: 500, body: {errorType: "internal_server_error"}.to_json) }

      it "raises" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
      end
    end

    context "when CDP answers a JSON array" do
      before { stub_answer("verify", status: 200, body: "[]") }

      it "raises" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
      end
    end

    context "when CDP answers something other than JSON" do
      before { stub_answer("verify", status: 200, body: "<html></html>") }

      it "raises" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
      end
    end

    context "when a success carries no verdict" do
      before { stub_answer("verify", status: 200, body: "{}") }

      it "raises" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
      end

      it "logs it" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
        expect(Rails.logger).to have_received(:warn).with("X402::Facilitator::CoinbaseCdpAdapter call failed operation=verify reason=malformed_response status=200")
      end
    end

    context "when a success carries a verdict that is not a boolean" do
      before { stub_answer("verify", status: 200, body: {isValid: "true"}.to_json) }

      it "raises" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
      end
    end

    context "when the stored secret is not a key" do
      subject(:adapter) { described_class.new(api_key_id: cdp_api_key_id, api_key_secret: "not a key") }

      it "raises instead of reporting CDP unavailable" do
        expect { verification }.to raise_error(OpenSSL::PKey::PKeyError)
      end
    end

    context "when the call times out" do
      before { stub_request(:post, "#{cdp_facilitator_url}/verify").to_raise(Net::ReadTimeout) }

      it "raises" do
        expect { verification }.to raise_error(X402::Facilitator::UnavailableError)
      end
    end
  end

  describe "#settle" do
    subject(:settlement) { adapter.settle(payment:, payment_requirements:) }

    it "is settled with the transaction" do
      expect(settlement).to have_attributes(
        outcome: :settled,
        transaction: "0xefad33f01282b3a8b18893a9eb0aecbc2fc210ffcfa7fda7ca79f14c8822963a",
        network: "eip155:84532",
        payer: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2"
      )
    end

    it "logs nothing" do
      settlement

      expect(Rails.logger).not_to have_received(:warn)
    end

    context "with a spy on the HTTP client" do
      before { allow(LagoHttpClient::Client).to receive(:new).and_call_original }

      it "settles behind the hard timeout" do
        settlement

        expect(LagoHttpClient::Client).to have_received(:new).with("#{cdp_facilitator_url}/settle", open_timeout: 5, read_timeout: 20)
      end
    end

    context "when CDP rejects the settle" do
      let(:fault) { :settle_fail_after_verify }

      it "stays unconfirmed with CDP's reason" do
        expect(settlement).to have_attributes(outcome: :unconfirmed_failure, error_reason: "invalid_exact_evm_signature", transaction: nil)
      end

      it "logs the failure with its duration" do
        settlement

        expect(Rails.logger).to have_received(:warn)
          .with(/call failed operation=settle reason=invalid_exact_evm_signature outcome=unconfirmed_failure network=eip155:84532 duration=\d+\.\d+\z/)
      end
    end

    context "when a rejection carries a hash" do
      before { stub_answer("settle", status: 400, body: {success: false, errorReason: "invalid_exact_evm_signature", transaction: "0x#{"cd" * 32}"}.to_json) }

      it "stays unconfirmed, without the hash" do
        expect(settlement).to have_attributes(outcome: :unconfirmed_failure, transaction: nil)
      end
    end

    context "when CDP says the nonce was already submitted" do
      before do
        stub_answer("settle", status: 400, body: {
          errorMessage: "authorization nonce already submitted; transaction already on-chain",
          errorReason: "invalid_payload",
          network: "eip155:84532",
          success: false,
          transaction: "0xefad33f01282b3a8b18893a9eb0aecbc2fc210ffcfa7fda7ca79f14c8822963a"
        }.to_json)
      end

      it "stays unconfirmed" do
        expect(settlement).to have_attributes(outcome: :unconfirmed_failure, transaction: nil, error_reason: "invalid_payload")
      end
    end

    context "when the settle failed on chain" do
      let(:fault) { :settle_failed_onchain }

      it "stays unconfirmed, without the hash" do
        expect(settlement).to have_attributes(outcome: :unconfirmed_failure, transaction: nil, error_reason: "settle_exact_failed_onchain")
      end
    end

    context "when a Solana simulation fails" do
      before do
        stub_answer("settle", status: 400, body: {
          errorMessage: "simulation failed: transaction would fail on-chain: AlreadyProcessed",
          errorReason: "invalid_exact_svm_payload_transaction_simulation_failed",
          success: false
        }.to_json)
      end

      it "stays unconfirmed" do
        expect(settlement.outcome).to eq(:unconfirmed_failure)
      end
    end

    %w[
      insufficient_funds
      invalid_payload
      invalid_exact_evm_payload_authorization_valid_before
      invalid_exact_evm_verification_failed
      invalid_exact_solana_transaction_confirmation_failed
      settle_exact_svm_transaction_confirmation_timed_out
    ].each do |cdp_reason|
      context "when CDP answers #{cdp_reason}" do
        before { stub_answer("settle", status: 400, body: {success: false, errorReason: cdp_reason}.to_json) }

        it "stays unconfirmed" do
          expect(settlement).to have_attributes(outcome: :unconfirmed_failure, error_reason: cdp_reason)
        end
      end
    end

    context "when CDP answers a reason Lago does not know" do
      before { stub_answer("settle", status: 200, body: {success: false, errorReason: "settle_exact_new_failure"}.to_json) }

      it "stays unconfirmed" do
        expect(settlement.outcome).to eq(:unconfirmed_failure)
      end

      it "logs CDP's reason" do
        settlement

        expect(Rails.logger).to have_received(:warn).with(/operation=settle reason=settle_exact_new_failure outcome=unconfirmed_failure duration=/)
      end
    end

    context "when the settle is pending" do
      let(:fault) { :settlement_pending }

      it "keeps the hash CDP broadcast" do
        expect(settlement).to have_attributes(outcome: :settlement_pending, transaction: "0x#{"cd" * 32}", network: "eip155:84532")
      end
    end

    context "when a pending settle arrives as a 200" do
      before { stub_answer("settle", status: 200, body: {success: false, errorReason: "settlement_pending", transaction: "0x#{"cd" * 32}"}.to_json) }

      it "is still pending" do
        expect(settlement).to have_attributes(outcome: :settlement_pending, transaction: "0x#{"cd" * 32}")
      end
    end

    context "when CDP answers a generic 500" do
      let(:fault) { :settle_server_error }

      it "is a server error" do
        expect(settlement.outcome).to eq(:server_error)
      end

      it "is not retried" do
        settlement

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).to have_been_made.once
      end
    end

    context "when CDP reports success without a hash" do
      before { stub_answer("settle", status: 200, body: {success: true}.to_json) }

      it "is a server error" do
        expect(settlement.outcome).to eq(:server_error)
      end
    end

    context "when CDP answers something other than JSON" do
      before { stub_answer("settle", status: 200, body: "<html></html>") }

      it "is a server error" do
        expect(settlement.outcome).to eq(:server_error)
      end
    end

    context "when the settle times out" do
      let(:fault) { :settle_timeout }

      it "has no response" do
        expect(settlement.outcome).to eq(:no_response)
      end

      it "is not retried" do
        settlement

        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).to have_been_made.once
      end

      it "logs it" do
        settlement

        expect(Rails.logger).to have_received(:warn).with(/operation=settle reason=no_response outcome=no_response duration=/)
      end
    end

    [Net::OpenTimeout, Errno::ECONNRESET, Errno::EPIPE, SocketError].each do |transport_error|
      context "when the connection fails with #{transport_error}" do
        before { stub_request(:post, "#{cdp_facilitator_url}/settle").to_raise(transport_error) }

        it "has no response" do
          expect(settlement.outcome).to eq(:no_response)
        end
      end
    end

    context "when the stored secret is not a key" do
      subject(:adapter) { described_class.new(api_key_id: cdp_api_key_id, api_key_secret: "not a key") }

      it "raises instead of reporting no response" do
        expect { settlement }.to raise_error(OpenSSL::PKey::PKeyError)
      end

      it "sends nothing" do
        expect { settlement }.to raise_error(OpenSSL::PKey::PKeyError)
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when the body cannot be serialised" do
      let(:payment) { x402_evm_payment.merge("memo" => (+"\xFF").force_encoding("UTF-8")) }

      it "raises instead of reporting no response" do
        expect { settlement }.to raise_error(JSON::GeneratorError)
      end

      it "sends nothing" do
        expect { settlement }.to raise_error(JSON::GeneratorError)
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when CDP answers 401" do
      before { stub_answer("settle", status: 401, body: "Unauthorized") }

      it "raises a credential error" do
        expect { settlement }.to raise_error(X402::Facilitator::CredentialError)
      end
    end

    context "when CDP answers 402" do
      before { stub_answer("settle", status: 402, body: {errorType: "payment_method_required"}.to_json) }

      it "raises a credential error" do
        expect { settlement }.to raise_error(X402::Facilitator::CredentialError) { |error| expect(error.http_status).to eq(402) }
      end
    end

    context "when screening declines the settle" do
      before { stub_answer("settle", status: 403, body: {errorType: "kyt_risk_detected"}.to_json) }

      it "raises a credential error" do
        expect { settlement }.to raise_error(X402::Facilitator::CredentialError) { |error| expect(error.error_type).to eq("kyt_risk_detected") }
      end
    end

    context "when CDP answers 429" do
      before { stub_answer("settle", status: 429, body: {errorType: "rate_limit_exceeded"}.to_json) }

      it "raises a rate-limit error" do
        expect { settlement }.to raise_error(X402::Facilitator::RateLimitError)
      end
    end
  end

  describe "#supported" do
    subject(:supported) { adapter.supported }

    it "lists the kinds" do
      expect(supported.fee_payer(network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1")).to eq("GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb")
    end

    it "signs a token bound to the GET" do
      supported

      expect(a_request(:get, "#{cdp_facilitator_url}/supported").with { |request| jwt_claims(request)["uri"] == "GET api.cdp.coinbase.com/platform/v2/x402/supported" }).to have_been_made
    end

    context "when CDP answers 401" do
      before { stub_answer("supported", status: 401, body: "Unauthorized") }

      it "raises a credential error" do
        expect { supported }.to raise_error(X402::Facilitator::CredentialError)
      end
    end

    ["<html></html>", "[]", "{}", {kinds: {network: "eip155:84532"}}.to_json, {kinds: ["exact"]}.to_json].each do |body|
      context "when CDP answers #{body}" do
        before { stub_answer("supported", status: 200, body:) }

        it "raises" do
          expect { supported }.to raise_error(X402::Facilitator::UnavailableError)
        end
      end
    end

    context "when CDP answers 503" do
      before { stub_answer("supported", status: 503, body: "") }

      it "raises" do
        expect { supported }.to raise_error(X402::Facilitator::UnavailableError)
      end
    end
  end
end
