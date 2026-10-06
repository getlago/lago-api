# frozen_string_literal: true

require "rails_helper"

describe X402::Settlements::SettleService do
  include_context "with an x402 payment"

  describe "#call" do
    subject(:result) { described_class.call(verified_payment:, kind:, invoice:, purchase_settings:) }

    let(:payment) { x402_evm_payment }
    let(:payment_requirements) { x402_evm_requirements }
    let(:x402_evm_requirements) { super().merge("amount" => "1050001") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "1050001"}}) }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:verified_payment) do
      X402::Settlements::VerifiedPayment.new(
        connection: x402_connection,
        payment_payload: X402::PaymentPayload.new(payment:, payment_requirements:),
        payer_address:,
        payment_digest: "digest",
        verify_response: {"isValid" => true}
      )
    end
    let(:kind) { :credit_purchase }
    let(:invoice) { nil }
    let(:purchase_settings) { {"plan_code" => "agent_api", "wallet_code" => "agent_credits"} }
    let(:fault) { nil }
    let(:other_connection) { create(:x402_connection, organization:) }
    let(:settlement) { result.settlement.reload }

    before do
      travel_to(Time.zone.at(1_789_649_271))
      allow(Rails.logger).to receive(:warn)
      stub_cdp_facilitator(fault:)
    end

    def settle_request
      a_request(:post, "#{cdp_facilitator_url}/settle").with(body: {x402Version: 2, paymentPayload: payment, paymentRequirements: payment_requirements}.to_json)
    end

    shared_examples "a pending outcome" do
      it "reports a pending outcome" do
        expect(result.outcome).to eq(:pending)
      end

      it "reports no transaction hash" do
        expect(result.transaction_hash).to be_nil
      end

      it "leaves the row pending" do
        expect(settlement.status).to eq("pending")
      end
    end

    shared_examples "a refusal before settle" do |errors|
      it "fails with the exact messages" do
        expect(result.error.messages).to eq(errors)
      end

      it "does not request /settle" do
        result
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "with a settled answer" do
      let(:recorded) { [] }

      before do
        stub_request(:post, "#{cdp_facilitator_url}/settle").to_return do
          recorded << X402::Settlement.pluck(:status, :payment_digest)
          {status: 200, body: cdp_fixture("settle_success")}
        end
      end

      it "has the pending row in place when /settle is called" do
        result
        expect(recorded).to eq([[["pending", "digest"]]])
      end

      it "reports a settled outcome" do
        expect(result.outcome).to eq(:settled)
      end

      it "reports the transaction hash" do
        expect(result.transaction_hash).to eq(JSON.parse(cdp_fixture("settle_success"))["transaction"])
      end

      it "leaves the row pending without hash or error" do
        expect(settlement).to have_attributes(status: "pending", transaction_hash: nil, error_reason: nil)
      end

      it "records the payment terms" do
        expect(settlement).to have_attributes(
          organization_id: organization.id,
          x402_connection_id: x402_connection.id,
          kind: "credit_purchase",
          network: "eip155:84532",
          asset: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
          payer_address:,
          payee_address: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
          settled_amount_atomic: 1_050_001,
          settled_amount_cents: 105,
          purchase_settings:,
          payment_digest: "digest"
        )
      end

      it "stores the exchange in the payload" do
        expect(settlement.payload.keys).to match_array(%w[payment payment_requirements verify_response settle_response])
      end

      it "requests /settle once with the original objects" do
        result
        expect(settle_request).to have_been_made.once
      end

      it "schedules the reconciliation after the payment expires" do
        expect(settlement.reconcile_after).to eq(Time.zone.at(1_789_649_331) + 30.seconds)
      end

      context "with the bazaar extension" do
        let(:x402_evm_payment) { super().merge("extensions" => {"bazaar" => {"discoverable" => true}}) }

        it "forwards the extension" do
          result
          expect(settle_request).to have_been_made.once
        end
      end
    end

    context "with a failure after verify" do
      let(:fault) { :settle_fail_after_verify }

      it_behaves_like "a pending outcome"

      it "records the reason" do
        expect(settlement.error_reason).to eq("invalid_exact_evm_signature")
      end
    end

    context "with a failure on chain" do
      let(:fault) { :settle_failed_onchain }

      it_behaves_like "a pending outcome"

      it "keeps the hash out of the column" do
        expect(settlement.transaction_hash).to be_nil
      end

      it "keeps the hash in the payload" do
        expect(settlement.payload["settle_response"]["transaction"]).to eq("0x#{"cd" * 32}")
      end
    end

    context "with a KYT decline" do
      let(:fault) { :settle_kyt_decline }

      it_behaves_like "a pending outcome"

      it "records the reason" do
        expect(settlement.error_reason).to eq("kyt_risk_detected")
      end
    end

    context "with a pending settlement" do
      let(:fault) { :settlement_pending }

      it_behaves_like "a pending outcome"

      it "stores the hash in the column" do
        expect(settlement.transaction_hash).to eq("0x#{"cd" * 32}")
      end

      it "records the reason" do
        expect(settlement.error_reason).to eq("settlement_pending")
      end
    end

    context "with a pending settlement without a hash" do
      before { stub_cdp_answer("/settle", status: 500, body: {success: false, errorReason: "settlement_pending", network: "eip155:84532", transaction: ""}) }

      it_behaves_like "a pending outcome"

      it "stores no hash" do
        expect(settlement.transaction_hash).to be_nil
      end

      it "records the reason" do
        expect(settlement.error_reason).to eq("settlement_pending")
      end
    end

    context "with a dropped connection" do
      let(:fault) { :settle_dropped }

      it_behaves_like "a pending outcome"

      it "records the reason" do
        expect(settlement.error_reason).to eq("no_response")
      end

      it "leaves the hash column empty" do
        expect(settlement.transaction_hash).to be_nil
      end
    end

    context "with a timeout" do
      let(:fault) { :settle_timeout }

      it_behaves_like "a pending outcome"

      it "records the reason" do
        expect(settlement.error_reason).to eq("no_response")
      end
    end

    context "with a server error" do
      let(:fault) { :settle_server_error }

      it_behaves_like "a pending outcome"

      it "records the reason" do
        expect(settlement.error_reason).to eq("server_error")
      end

      it "requests /settle once" do
        result
        expect(settle_request).to have_been_made.once
      end
    end

    [401, 402, 403].each do |status|
      context "with a #{status} answer" do
        before { stub_cdp_answer("/settle", status:, body: {errorType: "unauthorized", errorMessage: "no"}) }

        it_behaves_like "a pending outcome"

        it "records the reason" do
          expect(settlement.error_reason).to eq("credential_error")
        end
      end
    end

    context "with a 429 answer" do
      before { stub_cdp_answer("/settle", status: 429, body: {errorType: "rate_limit_exceeded", errorMessage: "slow down"}) }

      it_behaves_like "a pending outcome"

      it "records the reason" do
        expect(settlement.error_reason).to eq("rate_limited")
      end
    end

    context "when a pending attempt holds the digest" do
      before { create(:x402_settlement, :pending, organization:, x402_connection: other_connection, payment_digest: "digest") }

      it_behaves_like "a refusal before settle", {base: ["payment_already_recorded"]}

      it "writes no new row" do
        result
        expect(X402::Settlement.count).to eq(1)
      end
    end

    context "when a settled attempt holds the digest" do
      before { create(:x402_settlement, organization:, x402_connection: other_connection, payment_digest: "digest") }

      it_behaves_like "a refusal before settle", {base: ["payment_already_recorded"]}

      it "writes no new row" do
        result
        expect(X402::Settlement.count).to eq(1)
      end
    end

    context "when a pending attempt of the same payer holds the digest" do
      before { create(:x402_settlement, :pending, organization:, x402_connection: other_connection, payment_digest: "digest", payer_address:) }

      it "fails with a race code" do
        expect(described_class::RACE_CODES.values).to include(result.error.messages[:base].first)
      end

      it "writes no new row" do
        result
        expect(X402::Settlement.count).to eq(1)
      end
    end

    context "when the insert hits an unknown unique index" do
      before do
        allow(X402::Settlement).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new('duplicate key value violates unique constraint "some_other_index"'))
      end

      it "re-raises" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "does not request /settle" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when only a failed attempt holds the digest" do
      before { create(:x402_settlement, :failed, organization:, x402_connection: other_connection, payment_digest: "digest") }

      it "settles" do
        expect(result.outcome).to eq(:settled)
      end
    end

    context "when another organization holds the digest" do
      before { create(:x402_settlement, :pending, payment_digest: "digest") }

      it "settles" do
        expect(result.outcome).to eq(:settled)
      end
    end

    context "when the payer has a pending credit purchase" do
      before { create(:x402_settlement, :pending, organization:, x402_connection: other_connection, payer_address:) }

      it_behaves_like "a refusal before settle", {base: ["credit_purchase_pending"]}
    end

    context "when the payer has a pending invoice payment" do
      before { create(:x402_settlement, :pending, :invoice_payment, organization:, x402_connection: other_connection, payer_address:) }

      it "settles" do
        expect(result.outcome).to eq(:settled)
      end
    end

    context "with an invoice payment" do
      let(:kind) { :invoice_payment }
      let(:invoice) { create(:invoice, organization:) }
      let(:purchase_settings) { nil }

      it "links the invoice" do
        expect(settlement.invoice).to eq(invoice)
      end

      context "when an earlier attempt is pending for the invoice" do
        before { create(:x402_settlement, :pending, :invoice_payment, organization:, x402_connection: other_connection, invoice:) }

        it_behaves_like "a refusal before settle", {base: ["invoice_payment_pending"]}
      end
    end

    context "with a Solana payment" do
      let(:payment) { x402_svm_payment }
      let(:payment_requirements) { x402_svm_requirements }
      let(:x402_svm_requirements) { super().merge("amount" => "10000") }
      let(:payer_address) { x402_svm_payer }

      it "schedules the reconciliation after the expiry proof" do
        expect(settlement.reconcile_after).to eq(Time.zone.at(1_789_649_271) + 120.seconds)
      end

      it "records the amount" do
        expect(settlement.settled_amount_atomic).to eq(10_000)
      end

      it "records the payee" do
        expect(settlement.payee_address).to eq("HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG")
      end
    end

    context "with an unknown kind" do
      let(:kind) { "refund" }

      it "fails on the kind" do
        expect(result.error.messages).to eq(kind: ["value_is_invalid"])
      end

      it "does not request /settle" do
        result
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
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

      it "does not request /settle" do
        result
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end

    context "when called inside a transaction" do
      subject(:result) do
        ApplicationRecord.transaction { described_class.call(verified_payment:, kind:, invoice:, purchase_settings:) }
      end

      it "raises" do
        expect { result }.to raise_error(RuntimeError, /outside a database transaction/)
      end

      it "does not request /settle" do
        expect { result }.to raise_error(RuntimeError)
        expect(a_request(:post, "#{cdp_facilitator_url}/settle")).not_to have_been_made
      end
    end
  end
end
