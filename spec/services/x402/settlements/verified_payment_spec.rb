# frozen_string_literal: true

require "rails_helper"

describe X402::Settlements::VerifiedPayment do
  subject(:verified_payment) do
    described_class.new(
      connection: x402_connection,
      payment_payload:,
      payer_address: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
      payment_digest: "digest",
      verify_response: {"isValid" => true}
    )
  end

  include_context "with an x402 payment"

  let(:payment) { x402_evm_payment }
  let(:payment_requirements) { x402_evm_requirements }
  let(:payment_payload) { X402::PaymentPayload.new(payment:, payment_requirements:) }

  context "with an EVM payment" do
    it do
      expect(verified_payment).to have_attributes(
        network: "eip155:84532",
        family: :evm,
        asset: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        payment:,
        payment_requirements:,
        payee_address: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
        settled_amount_atomic: 1000,
        settled_amount_cents: 0
      )
    end

    context "when the authorization value differs from the requirement amount" do
      let(:x402_evm_requirements) { super().merge("amount" => "1050000") }
      let(:x402_evm_payment) do
        super().deep_merge("payload" => {"authorization" => {"value" => "1050001"}})
      end

      it "settles the authorized value, floored to cents" do
        expect(verified_payment).to have_attributes(settled_amount_atomic: 1_050_001, settled_amount_cents: 105)
      end
    end
  end

  context "with a Solana payment" do
    let(:payment) { x402_svm_payment }
    let(:payment_requirements) { x402_svm_requirements }
    let(:x402_svm_requirements) { super().merge("amount" => "10000") }

    it do
      expect(verified_payment).to have_attributes(
        family: :svm,
        payee_address: "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG",
        settled_amount_atomic: 10_000,
        settled_amount_cents: 1
      )
    end
  end
end
