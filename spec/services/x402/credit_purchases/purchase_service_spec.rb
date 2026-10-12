# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::PurchaseService do
  include_context "with an x402 payment"

  describe "#call" do
    subject(:result) { described_class.call(organization:, params:) }

    let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
    let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
    let(:payee_address) { x402_connection.payout_addresses["evm"] }
    let(:x402_evm_requirements) { super().merge("amount" => "10000000") }
    let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "10000000"}}) }
    let(:payment) { x402_evm_payment }
    let(:payment_requirements) { x402_evm_requirements }
    let(:wallet_shape) { {"name" => "Agent credits", "rate_amount" => "0.001", "currency" => "USD"} }
    let(:params) do
      {
        connection_code: x402_connection.code, plan_code: "agent_api", wallet_code: "agent_credits",
        wallet: wallet_shape.symbolize_keys, payment:, payment_requirements:
      }
    end
    let(:fault) { nil }
    let(:settled_hash) { JSON.parse(cdp_fixture("settle_success"))["transaction"] }
    let(:digest) do
      X402::Payments::ComputeDigestService.call(payment: x402_evm_payment, network: x402_evm_requirements["network"], asset: x402_evm_requirements["asset"]).digest
    end
    let(:stored_settings) { {"plan_code" => "agent_api", "wallet_code" => "agent_credits", "wallet" => wallet_shape} }

    before do
      travel_to(Time.zone.at(1_789_649_271))
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:info)
      stub_cdp_facilitator(fault:)
      plan
    end

    def verify_request
      a_request(:post, "#{cdp_facilitator_url}/verify")
    end

    def settle_request
      a_request(:post, "#{cdp_facilitator_url}/settle")
    end

    shared_examples "a refusal before settle" do |messages|
      it "fails with the refusal" do
        expect(result.error.messages).to eq(messages)
      end

      it "writes nothing" do
        expect { result }.not_to change { [X402::Settlement.count, Customer.count, WalletTransaction.count] }
      end

      it "does not request /settle" do
        result
        expect(settle_request).not_to have_been_made
      end
    end

    shared_examples "a pending purchase" do
      it "answers the pending row" do
        expect(result.settlement).to have_attributes(status: "pending", customer_id: nil, wallet_transaction_id: nil)
      end

      it "is not a replay" do
        expect(result.replayed).to be(false)
      end

      it "grants nothing" do
        expect { result }.not_to change(WalletTransaction, :count)
      end
    end

    context "with a first purchase" do
      it "settles the purchase" do
        expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: settled_hash)
      end

      it "is not a replay" do
        expect(result.replayed).to be(false)
      end

      it "grants the credits" do
        expect(result.settlement.wallet_transaction.wallet.reload).to have_attributes(code: "agent_credits", balance_cents: 1000, credits_balance: BigDecimal("10000"))
      end

      it "opens the agent's subscription" do
        expect(result.settlement.subscription).to have_attributes(plan:, external_id: "x402_#{payer_address}_agent_api")
      end

      it "stores the purchase settings" do
        expect(result.settlement.reload.purchase_settings).to eq(stored_settings)
      end

      it "requests /verify once" do
        result
        expect(verify_request).to have_been_made.once
      end

      it "requests /settle once" do
        result
        expect(settle_request).to have_been_made.once
      end
    end

    context "with keys outside the wallet shape" do
      let(:wallet_shape) { super().merge("expiration_at" => "2030-01-01T00:00:00Z", "allowed_fee_types" => ["charge"]) }

      it "stores only the shape keys" do
        expect(result.settlement.reload.purchase_settings["wallet"]).to eq("name" => "Agent credits", "rate_amount" => "0.001", "currency" => "USD")
      end
    end

    context "with a Solana payment" do
      let(:x402_svm_requirements) { super().merge("amount" => "10000000") }
      let(:payment) { x402_svm_payment }
      let(:payment_requirements) { x402_svm_requirements }
      let(:signature) { X402::Base58.encode("\x01".b * 64) }

      before do
        stub_cdp_answer("/verify", status: 200, body: {isValid: true, payer: x402_svm_payer})
        stub_cdp_answer("/settle", status: 200, body: {success: true, transaction: signature, network: x402_svm_requirements["network"], payer: x402_svm_payer})
      end

      it "settles the purchase" do
        expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: signature, payer_address: x402_svm_payer)
      end

      it "grants the payer" do
        expect(result.settlement.customer).to have_attributes(x402_agent_address: x402_svm_payer)
      end
    end

    context "without a payment" do
      let(:payment) { nil }

      it_behaves_like "a refusal before settle", {payment: ["invalid_payment"]}
    end

    context "without payment requirements" do
      let(:payment_requirements) { nil }

      it_behaves_like "a refusal before settle", {payment_requirements: ["invalid_payment_requirements"]}
    end

    context "with a network outside CAIP-2" do
      let(:payment_requirements) { x402_evm_requirements.merge("network" => "base-sepolia") }

      it_behaves_like "a refusal before settle", {payment: ["unsupported_network"]}
    end

    context "with an unknown connection" do
      let(:params) { super().merge(connection_code: "unknown") }

      it "fails with connection_not_found" do
        expect(result.error.error_code).to eq("connection_not_found")
      end
    end

    context "with a discarded connection" do
      let(:x402_connection) { create(:x402_connection, :discarded, organization:) }

      it "fails with connection_not_found" do
        expect(result.error.error_code).to eq("connection_not_found")
      end
    end

    context "with an unknown plan" do
      let(:params) { super().merge(plan_code: "unknown") }

      it "fails with plan_not_found" do
        expect(result.error.error_code).to eq("plan_not_found")
      end

      it "does not request /verify" do
        result
        expect(verify_request).not_to have_been_made
      end
    end

    context "with a /verify reject" do
      let(:fault) { :verify_reject }

      it_behaves_like "a refusal before settle", {payment: ["invalid_exact_evm_payload_signature"]}
    end

    context "with a facilitator outage on /verify" do
      before { stub_cdp_answer("/verify", status: 500, body: {errorType: "internal_server_error", correlationId: "corr-1"}) }

      it "fails with a third-party error" do
        expect(result.error).to have_attributes(third_party: "coinbase_cdp", error_code: "unavailable_error")
      end

      it "writes nothing" do
        expect { result }.not_to change(X402::Settlement, :count)
      end
    end

    context "with a /verify payer other than the payment's" do
      before { stub_cdp_answer("/verify", status: 200, body: {isValid: true, payer: "0x#{"11" * 20}"}) }

      it "fails with a retryable third-party error" do
        expect(result.error).to have_attributes(error_code: "unavailable_error", error_message: "unavailable_error: verify: payer_mismatch")
      end
    end

    context "with an unknown payer whose external id another customer holds" do
      before { create(:customer, organization:, external_id: "x402_#{payer_address}") }

      it_behaves_like "a refusal before settle", {base: ["buyer_external_id_taken"]}
    end

    context "with a wallet shape outside USD" do
      let(:wallet_shape) { super().merge("currency" => "EUR") }

      it_behaves_like "a refusal before settle", {wallet: ["currency_not_supported"]}
    end

    context "with another purchase of the payer pending" do
      before { create(:x402_settlement, :pending, organization:, x402_connection:, payee_address:, payer_address:) }

      it_behaves_like "a refusal before settle", {base: ["credit_purchase_pending"]}
    end

    context "with settlement_pending" do
      let(:fault) { :settlement_pending }

      it_behaves_like "a pending purchase"

      it "answers when reconciliation runs" do
        expect(result.settlement.reconcile_after).to eq(Time.zone.at(1_789_649_331) + X402::Settlements::SettleService::RECONCILE_MARGIN)
      end
    end

    context "with a settle timeout" do
      let(:fault) { :settle_timeout }

      it_behaves_like "a pending purchase"
    end

    context "with the settled hash held by another settlement" do
      before { create(:x402_settlement, transaction_hash: settled_hash) }

      it_behaves_like "a pending purchase"

      it "logs the failed flip" do
        result
        expect(Rails.logger).to have_received(:warn).with(a_string_including("reason=flip_failed error=ActiveRecord::RecordNotUnique"))
      end
    end

    context "with a grant failing after the settle" do
      before { allow(X402::Subscriptions::ResolveService).to receive(:call!).and_raise(ActiveRecord::LockWaitTimeout) }

      it "fails with credit_grant_failed" do
        expect(result.error.messages).to eq(base: ["credit_grant_failed"])
      end

      it "keeps the settled row for a replay" do
        result
        expect(X402::Settlement.sole).to have_attributes(status: "settled", transaction_hash: settled_hash, wallet_transaction_id: nil)
      end

      it "requests /settle once" do
        result
        expect(settle_request).to have_been_made.once
      end
    end

    context "with the plan deleted after the settle" do
      before do
        stub_request(:post, "#{cdp_facilitator_url}/settle").to_return do
          plan.discard!
          {status: 200, body: cdp_fixture("settle_success")}
        end
      end

      it "fails with credit_grant_failed" do
        expect(result.error.messages).to eq(base: ["credit_grant_failed"])
      end

      it "logs the grant's refusal" do
        result
        expect(Rails.logger).to have_received(:warn).with(a_string_including("reason=grant_failed error=BaseService::NotFoundFailure message=plan_not_found"))
      end
    end
  end
end
