# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::RecordService do
  include_context "with an x402 payment"

  describe "#call" do
    subject(:result) { described_class.call(verified_payment:, settle_response:, purchase_settings:, request_key_digest:) }

    let(:payment) { x402_evm_payment }
    let(:payment_requirements) { x402_evm_requirements }
    let(:x402_evm_requirements) { super().merge("amount" => "1050001") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "1050001"}}) }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:verify_response) { nil }
    let(:verified_payment) do
      X402::Settlements::VerifiedPayment.new(
        connection: x402_connection,
        payment_payload: X402::PaymentPayload.new(payment:, payment_requirements:),
        payer_address:,
        payment_digest: "digest",
        verify_response:
      )
    end
    let(:gate_hash) { "0x#{"CD" * 32}" }
    let(:stored_hash) { "0x#{"cd" * 32}" }
    let(:settle_response) { {"success" => true, "transaction" => gate_hash, "network" => "eip155:84532", "payer" => payer_address} }
    let(:purchase_settings) { {"plan_code" => "agent_api", "wallet_code" => "agent_credits"} }
    let(:request_key_digest) { X402::Settlement.request_key_digest("agent-request-0001") }
    let(:other_connection) { create(:x402_connection, organization:) }

    shared_examples "a refusal" do |messages|
      it "fails with the refusal" do
        expect(result.error.messages).to eq(messages)
      end

      it "writes no new row" do
        expect { result }.not_to change(X402::Settlement, :count)
      end
    end

    context "with a payment no row holds" do
      it "records a settled credit purchase made by the merchant" do
        expect(result.settlement.reload).to have_attributes(
          organization_id: organization.id,
          x402_connection_id: x402_connection.id,
          kind: "credit_purchase",
          status: "settled",
          settled_by: "merchant",
          transaction_hash: stored_hash,
          network: "eip155:84532",
          asset: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
          payer_address:,
          payee_address: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
          settled_amount_atomic: 1_050_001,
          settled_amount_cents: 105,
          payment_digest: "digest",
          request_key_digest:,
          purchase_settings:,
          reconcile_after: nil,
          customer_id: nil,
          wallet_transaction_id: nil
        )
      end

      it "keeps the payment and the gate's settle response as sent" do
        expect(result.settlement.reload.payload).to eq("payment" => payment, "payment_requirements" => payment_requirements, "settle_response" => settle_response)
      end

      context "with the gate's verify answer" do
        let(:verify_response) { {"isValid" => true, "payer" => payer_address} }

        it "keeps it too" do
          expect(result.settlement.reload.payload["verify_response"]).to eq(verify_response)
        end
      end
    end

    context "when a pending purchase of the same payer exists" do
      before { create(:x402_settlement, :pending, organization:, x402_connection: other_connection, payer_address:) }

      it "records the purchase" do
        expect(result.settlement.reload.status).to eq("settled")
      end
    end

    context "when a row holds the digest" do
      before { create(:x402_settlement, organization:, x402_connection: other_connection, payment_digest: "digest") }

      it_behaves_like "a refusal", {base: ["payment_already_recorded"]}
    end

    context "when another organization's row holds the digest" do
      before { create(:x402_settlement, payment_digest: "digest") }

      it_behaves_like "a refusal", {base: ["payment_already_recorded"]}
    end

    context "when a row holds the transaction" do
      before { create(:x402_settlement, organization:, x402_connection: other_connection, transaction_hash: stored_hash) }

      it_behaves_like "a refusal", {settle_response: ["transaction_already_recorded"]}
    end

    context "when another organization's row holds the transaction" do
      before { create(:x402_settlement, transaction_hash: stored_hash) }

      it "records the purchase" do
        expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: stored_hash)
      end
    end

    context "when an invoice payment holds the transaction" do
      before { create(:x402_settlement, :invoice_payment, organization:, x402_connection: other_connection, transaction_hash: stored_hash) }

      it_behaves_like "a refusal", {settle_response: ["transaction_already_recorded"]}
    end

    context "with a Solana payment" do
      let(:payment) { x402_svm_payment }
      let(:payment_requirements) { x402_svm_requirements }
      let(:payer_address) { x402_svm_payer }
      let(:signature) { "7scJSNzkdyryaFQcfRX52upVRridoUijgMNaUmLBtJTxB9iCjmEDk2Mk54eEuTYoPqAgdtajPvxDMk9RFimsZ93" }
      let(:settle_response) { {"success" => true, "transaction" => signature, "network" => x402_svm_requirements["network"]} }

      it "keeps the signature's case" do
        expect(result.settlement.reload.transaction_hash).to eq(signature)
      end
    end

    context "when the insert hits an unknown unique index" do
      before do
        allow(X402::Settlement).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new('duplicate key value violates unique constraint "some_other_index"'))
      end

      it "re-raises" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with a connection paying out to another address" do
      let(:x402_connection) do
        create(
          :x402_connection,
          organization:,
          networks: ["eip155:84532"],
          payout_addresses: {"evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"},
          cdp_api_key_id:,
          cdp_api_key_secret:
        )
      end

      it "reports the payee" do
        expect(result.error.messages).to include(payee_address: ["not_connection_payout_address"])
      end

      it "writes no row" do
        expect { result }.not_to change(X402::Settlement, :count)
      end
    end
  end
end
