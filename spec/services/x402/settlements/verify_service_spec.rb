# frozen_string_literal: true

require "rails_helper"

describe X402::Settlements::VerifyService do
  include_context "with an x402 payment"
  include SolanaTransactionBuilder

  describe "#call" do
    subject(:result) { described_class.call(connection: x402_connection, payment:, payment_requirements:) }

    let(:payment) { x402_evm_payment }
    let(:payment_requirements) { x402_evm_requirements }
    let(:x402_evm_requirements) { super().merge("amount" => "1050001") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "1050001"}}) }
    let(:fault) { nil }
    let(:base_asset) { "0x036CbD53842c5426634e7929541eC2318f3dCF7e" }
    let(:other_pay_to) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }

    before do
      travel_to(Time.zone.at(1_789_649_271))
      allow(Rails.logger).to receive(:warn)
      stub_cdp_facilitator(fault:)
    end

    def verify_request(body = {x402Version: 2, paymentPayload: payment, paymentRequirements: payment_requirements}.to_json)
      a_request(:post, "#{cdp_facilitator_url}/verify").with(body:)
    end

    def authorization_override(fields)
      x402_evm_payment.deep_merge("payload" => {"authorization" => fields})
    end

    shared_examples "a refusal before verify" do |errors|
      it "refuses with the exact messages" do
        expect(result.error.messages).to eq(errors)
      end

      it "does not request /verify" do
        result
        expect(a_request(:post, "#{cdp_facilitator_url}/verify")).not_to have_been_made
      end
    end

    context "with a valid EVM payment" do
      it "succeeds" do
        expect(result).to be_success
      end

      it "derives the payer" do
        expect(result.verified_payment.payer_address).to eq("0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2")
      end

      it "carries the digest" do
        digest = X402::Payments::ComputeDigestService.call!(payment:, network: "eip155:84532", asset: base_asset).digest

        expect(result.verified_payment.payment_digest).to eq(digest)
      end

      it "carries the parsed verify answer" do
        expect(result.verified_payment.verify_response).to eq(JSON.parse(cdp_fixture("verify_valid")))
      end

      it "writes no settlement" do
        result
        expect(X402::Settlement.count).to eq(0)
      end

      it "does not request /settle" do
        result
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end

      it "requests /verify once with the original objects" do
        result
        expect(verify_request).to have_been_made.once
      end

      context "with the bazaar extension" do
        let(:x402_evm_payment) { super().merge("extensions" => {"bazaar" => {"discoverable" => true}}) }

        it "forwards the extension unchanged" do
          result
          expect(verify_request).to have_been_made.once
        end
      end

      context "with symbol-keyed inputs" do
        let(:payment) { x402_evm_payment.deep_symbolize_keys }
        let(:payment_requirements) { x402_evm_requirements.deep_symbolize_keys }

        it "succeeds" do
          expect(result).to be_success
        end
      end

      context "with the asset in lowercase" do
        let(:x402_evm_requirements) { super().merge("asset" => base_asset.downcase) }

        it "succeeds" do
          expect(result).to be_success
        end
      end

      context "with the payTo in lowercase" do
        let(:x402_evm_requirements) { super().merge("payTo" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5".downcase) }

        it "succeeds" do
          expect(result).to be_success
        end
      end

      context "with the payer in lowercase" do
        let(:payment) { authorization_override("from" => "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2".downcase) }

        it "derives the EIP-55 payer" do
          expect(result.verified_payment.payer_address).to eq("0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2")
        end
      end
    end

    context "when the payment is not a hash" do
      let(:payment) { "payment" }

      it_behaves_like "a refusal before verify", {payment: ["invalid_payment"]}
    end

    context "when the requirements are not a hash" do
      let(:payment_requirements) { "requirements" }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_payment_requirements"]}
    end

    context "when the payment holds invalid UTF-8" do
      let(:payment) { x402_evm_payment.merge("resource" => "\xFF".dup.force_encoding(Encoding::UTF_8)) }

      it_behaves_like "a refusal before verify", {payment: ["invalid_payment"]}
    end

    context "when the payment holds a NUL in a nested value" do
      let(:payment) { x402_evm_payment.merge("extensions" => {"note" => "a\u0000b"}) }

      it_behaves_like "a refusal before verify", {payment: ["invalid_payment"]}
    end

    context "when the payment holds a NUL in a key" do
      let(:payment) { x402_evm_payment.merge("extensions" => {"a\u0000b" => "note"}) }

      it_behaves_like "a refusal before verify", {payment: ["invalid_payment"]}
    end

    context "when the payment holds a NUL in an array" do
      let(:payment) { x402_evm_payment.merge("extensions" => {"notes" => ["ok", "a\u0000b"]}) }

      it_behaves_like "a refusal before verify", {payment: ["invalid_payment"]}
    end

    context "when the requirements hold a NUL in extra" do
      let(:payment_requirements) { x402_evm_requirements.merge("extra" => {"name" => "a\u0000b"}) }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_payment_requirements"]}
    end

    context "with x402Version 1" do
      let(:payment) { x402_evm_payment.merge("x402Version" => 1) }

      it_behaves_like "a refusal before verify", {payment: ["unsupported_x402_version"]}
    end

    context "with another scheme" do
      let(:payment_requirements) { x402_evm_requirements.merge("scheme" => "upto") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["unsupported_scheme"]}
    end

    context "with a network the merchant does not offer" do
      let(:payment_requirements) { x402_evm_requirements.merge("network" => "eip155:8453") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["unsupported_network"]}
    end

    context "with an unknown network" do
      let(:payment_requirements) { x402_evm_requirements.merge("network" => "eip155:1") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["unsupported_network"]}
    end

    context "with another asset" do
      let(:payment_requirements) { x402_evm_requirements.merge("asset" => "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["unsupported_asset"]}
    end

    context "with another payTo" do
      let(:payment_requirements) { x402_evm_requirements.merge("payTo" => other_pay_to) }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_pay_to"]}
    end

    context "with an amount of zero" do
      let(:payment_requirements) { x402_evm_requirements.merge("amount" => "0") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_amount"]}
    end

    context "with an amount below a cent" do
      let(:payment_requirements) { x402_evm_requirements.merge("amount" => "9999") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_amount"]}
    end

    context "with a maxTimeoutSeconds of 0" do
      let(:payment_requirements) { x402_evm_requirements.merge("maxTimeoutSeconds" => 0) }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_max_timeout_seconds"]}
    end

    context "with a maxTimeoutSeconds of 61" do
      let(:payment_requirements) { x402_evm_requirements.merge("maxTimeoutSeconds" => 61) }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_max_timeout_seconds"]}
    end

    context "with a string maxTimeoutSeconds" do
      let(:payment_requirements) { x402_evm_requirements.merge("maxTimeoutSeconds" => "60") }

      it_behaves_like "a refusal before verify", {payment_requirements: ["invalid_max_timeout_seconds"]}
    end

    context "with an authorization without a nonce" do
      let(:payment) { x402_evm_payment.merge("payload" => x402_evm_payment["payload"].merge("authorization" => x402_evm_payment.dig("payload", "authorization").except("nonce"))) }

      it_behaves_like "a refusal before verify", {payment: ["invalid_authorization"]}
    end

    context "with a payer whose checksum is wrong" do
      let(:payment) { authorization_override("from" => "0xF4a43b9cc729c9E4E139CB86808f48e3eD09Dcb2") }

      it_behaves_like "a refusal before verify", {payment: ["invalid_authorization"]}
    end

    context "with an authorization paying another address" do
      let(:payment) { authorization_override("to" => other_pay_to) }

      it_behaves_like "a refusal before verify", {payment: ["invalid_pay_to"]}
    end

    describe "the validBefore cap" do
      context "when the agent's clock is right" do
        it "verifies" do
          expect(result).to be_success
        end
      end

      context "when the agent's clock is 1 second ahead" do
        let(:payment) { authorization_override("validBefore" => "1789649332") }

        it "verifies" do
          expect(result).to be_success
        end
      end

      context "when the agent's clock is 30 seconds ahead" do
        let(:payment) { authorization_override("validBefore" => "1789649361") }

        it "verifies" do
          expect(result).to be_success
        end
      end

      context "when the agent's clock is 31 seconds ahead" do
        let(:payment) { authorization_override("validBefore" => "1789649362") }

        it_behaves_like "a refusal before verify", {payment: ["invalid_valid_before"]}
      end

      context "with a maxTimeoutSeconds of 10" do
        let(:payment_requirements) { x402_evm_requirements.merge("maxTimeoutSeconds" => 10) }

        it_behaves_like "a refusal before verify", {payment: ["invalid_valid_before"]}
      end
    end

    context "with a Solana payment" do
      let(:payment) { x402_svm_payment }
      let(:payment_requirements) { x402_svm_requirements }
      let(:x402_svm_requirements) { super().merge("amount" => "10000") }
      let(:buyer) { x402_svm_payer }
      let(:token_program) { SolanaTransactionBuilder::TOKEN_PROGRAM }
      let(:solana_verify_answer) { {isValid: true, payer: x402_svm_payer} }

      before { stub_cdp_answer("/verify", status: 200, body: solana_verify_answer) }

      it "succeeds" do
        expect(result).to be_success
      end

      it "requests /verify once with the original objects" do
        result
        expect(verify_request).to have_been_made.once
      end

      it "derives the Solana signer" do
        expect(result.verified_payment.payer_address).to eq(x402_svm_payer)
      end

      context "with a durable nonce" do
        let(:durable_nonce_transaction) do
          build_solana_transaction(
            keys: ["D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM", buyer, SolanaTransactionBuilder::SYSTEM_PROGRAM, token_program],
            instructions: [{program: 2, accounts: [1, 0, 1], data: [4].pack("L<")}, {program: 3, accounts: [1, 1, 1, 1], data: transfer_checked_data(10_000)}],
            signatures: ["\x00".b * 64, "\x02".b * 64]
          )
        end
        let(:x402_svm_payment) { super().deep_merge("payload" => {"transaction" => Base64.strict_encode64(durable_nonce_transaction)}) }

        it_behaves_like "a refusal before verify", {payment: ["unsupported_transaction"]}
      end

      context "without a TransferChecked" do
        let(:x402_svm_payment) { super().deep_merge("payload" => {"transaction" => Base64.strict_encode64(build_solana_transaction(keys: [buyer], instructions: [], signatures: ["\x02".b * 64]))}) }

        it_behaves_like "a refusal before verify", {payment: ["unsupported_transaction"]}
      end

      context "when the authority does not sign" do
        let(:unsigned_authority_transaction) do
          build_solana_transaction(
            keys: ["D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM", buyer, token_program],
            instructions: [{program: 2, accounts: [1, 1, 1, 1], data: transfer_checked_data(10_000)}],
            signatures: ["\x00".b * 64]
          )
        end
        let(:x402_svm_payment) { super().deep_merge("payload" => {"transaction" => Base64.strict_encode64(unsigned_authority_transaction)}) }

        it_behaves_like "a refusal before verify", {payment: ["unsupported_transaction"]}
      end

      context "when the transaction is not base64" do
        let(:x402_svm_payment) { super().deep_merge("payload" => {"transaction" => "not base64!"}) }

        it_behaves_like "a refusal before verify", {payment: ["invalid_transaction"]}
      end

      context "when verify answers no payer" do
        let(:solana_verify_answer) { {isValid: true} }

        it "raises an unavailable error" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError) { |error| expect(error.error_type).to eq("payer_missing") }
        end

        it "writes no settlement" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(X402::Settlement.count).to eq(0)
        end

        it "does not request /settle" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
        end

        it "logs one warning" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(Rails.logger).to have_received(:warn).with("X402::Settlements::VerifyService call failed reason=payer_missing network=solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1").once
        end

        it "logs no other warning" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(Rails.logger).to have_received(:warn).once
        end
      end

      context "when verify answers another payer" do
        let(:solana_verify_answer) { {isValid: true, payer: "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG"} }

        it "raises an unavailable error" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError) { |error| expect(error.error_type).to eq("payer_mismatch") }
        end
      end
    end

    describe "the /verify answers on EVM" do
      context "when verify rejects the payment" do
        let(:fault) { :verify_reject }

        it "refuses with the reason" do
          expect(result.error.messages).to eq({payment: ["invalid_exact_evm_payload_signature"]})
        end

        it "logs only the adapter's warning" do
          result
          expect(Rails.logger).to have_received(:warn).once
        end
      end

      context "when verify declines on risk" do
        let(:fault) { :verify_kyt_decline }

        it "refuses with the reason" do
          expect(result.error.messages).to eq({payment: ["kyt_risk_detected"]})
        end
      end

      context "when verify times out" do
        before { stub_request(:post, "#{cdp_facilitator_url}/verify").to_raise(Net::ReadTimeout) }

        it "raises an unavailable error" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
        end

        it "writes nothing" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(X402::Settlement.count).to eq(0)
        end
      end

      context "when verify answers 401" do
        before { stub_cdp_answer("/verify", status: 401, body: {errorType: "unauthorized", errorMessage: "no"}) }

        it "raises a credential error" do
          expect { result }.to raise_error(X402::Facilitator::CredentialError)
        end

        it "writes nothing" do
          expect { result }.to raise_error(X402::Facilitator::CredentialError)
          expect(X402::Settlement.count).to eq(0)
        end
      end

      context "when verify answers 402" do
        before { stub_cdp_answer("/verify", status: 402, body: {errorType: "payment_method_required", errorMessage: "pay"}) }

        it "raises a credential error" do
          expect { result }.to raise_error(X402::Facilitator::CredentialError)
        end

        it "writes nothing" do
          expect { result }.to raise_error(X402::Facilitator::CredentialError)
          expect(X402::Settlement.count).to eq(0)
        end
      end

      context "when verify answers 429" do
        before { stub_cdp_answer("/verify", status: 429, body: {errorType: "rate_limit_exceeded", errorMessage: "slow"}) }

        it "raises a rate limit error" do
          expect { result }.to raise_error(X402::Facilitator::RateLimitError)
        end
      end

      context "when verify answers 500" do
        before { stub_cdp_answer("/verify", status: 500, body: {errorType: "internal_server_error", errorMessage: "boom"}) }

        it "raises an unavailable error" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
        end
      end
    end

    describe "the EVM payer" do
      context "when verify answers no payer" do
        let(:fault) { :verify_without_payer }

        it "is the authorization's from" do
          expect(result.verified_payment.payer_address).to eq("0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2")
        end
      end

      context "when verify answers the payer in lowercase" do
        before { stub_cdp_answer("/verify", status: 200, body: {isValid: true, payer: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2".downcase}) }

        it "succeeds" do
          expect(result).to be_success
        end
      end

      context "when verify answers another payer" do
        before { stub_cdp_answer("/verify", status: 200, body: {isValid: true, payer: other_pay_to}) }

        it "raises an unavailable error" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError) { |error| expect(error.error_type).to eq("payer_mismatch") }
        end

        it "logs one warning" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(Rails.logger).to have_received(:warn).with("X402::Settlements::VerifyService call failed reason=payer_mismatch network=eip155:84532").once
        end

        it "logs no other warning" do
          expect { result }.to raise_error(X402::Facilitator::UnavailableError)
          expect(Rails.logger).to have_received(:warn).once
        end
      end
    end
  end
end
