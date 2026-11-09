# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::PurchaseService do
  include_context "with an x402 payment"
  include SolanaTransactionBuilder

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
    let(:idempotency_key) { "agent-request-0001" }
    let(:other_key) { "agent-request-0002" }
    let(:params) do
      {
        connection_code: x402_connection.code, plan_code: "agent_api", wallet_code: "agent_credits",
        wallet: wallet_shape.symbolize_keys, payment:, payment_requirements:, idempotency_key:
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

    shared_examples "a replay refusal" do
      it_behaves_like "a refusal before settle", {base: ["payment_already_settled"]}

      it "answers no settlement" do
        expect(result.settlement).to be_nil
      end

      it "calls no facilitator" do
        result
        expect(verify_request).not_to have_been_made
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

      it "stores the digest of the request's key" do
        expect(result.settlement.reload.request_key_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(idempotency_key))
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

    context "without an idempotency key" do
      let(:params) { super().except(:idempotency_key) }

      it "settles the purchase" do
        expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: settled_hash)
      end

      it "stores no key digest" do
        expect(result.settlement.reload.request_key_digest).to be_nil
      end
    end

    context "with an idempotency key at the length bounds" do
      let(:idempotency_key) { "k" * 16 }

      it "settles the purchase" do
        expect(result.settlement.reload.status).to eq("settled")
      end

      context "with the longest key" do
        let(:idempotency_key) { "~" * 128 }

        it "settles the purchase" do
          expect(result.settlement.reload.status).to eq("settled")
        end
      end
    end

    context "with an idempotency key shorter than 16 characters" do
      let(:idempotency_key) { "k" * 15 }

      it_behaves_like "a refusal before settle", {idempotency_key: ["invalid_value"]}
    end

    context "with an idempotency key longer than 128 characters" do
      let(:idempotency_key) { "k" * 129 }

      it_behaves_like "a refusal before settle", {idempotency_key: ["invalid_value"]}
    end

    context "with an idempotency key outside printable ASCII" do
      let(:idempotency_key) { "agent-request-\u00e9001" }

      it_behaves_like "a refusal before settle", {idempotency_key: ["invalid_value"]}
    end

    context "with an idempotency key holding a control character" do
      let(:idempotency_key) { "agent-request\n0001" }

      it_behaves_like "a refusal before settle", {idempotency_key: ["invalid_value"]}
    end

    context "with an idempotency key that is not a string" do
      let(:idempotency_key) { 1_234_567_890_123_456 }

      it_behaves_like "a refusal before settle", {idempotency_key: ["invalid_value"]}
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

      context "with the payment pending under this request" do
        let(:svm_digest) { X402::Payments::ComputeDigestService.call(payment: x402_svm_payment, network: x402_svm_requirements["network"]).digest }
        let!(:settlement) do
          create(
            :x402_settlement, :solana, :pending, organization:, x402_connection:, payee_address: x402_connection.payout_addresses["svm"],
            payer_address: x402_svm_payer, payment_digest: svm_digest, purchase_settings: stored_settings, request_key: idempotency_key
          )
        end

        it "answers the pending row" do
          expect(result.settlement).to have_attributes(id: settlement.id, status: "pending")
        end

        it "is a replay" do
          expect(result.replayed).to be(true)
        end

        context "with the payment rebuilt from the landed transaction" do
          let(:params) { super().merge(idempotency_key: other_key) }

          it_behaves_like "a replay refusal"
        end
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

    context "with a testnet connection on an organization running on mainnet" do
      let(:organization) { create(:organization, feature_flags: ["x402_mainnet"]) }
      let(:x402_connection) do
        create(
          :x402_connection,
          :saved_before_switch,
          organization:,
          networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
          payout_addresses: {"evm" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5", "svm" => "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG"},
          cdp_api_key_id:,
          cdp_api_key_secret:
        )
      end

      it_behaves_like "a refusal before settle", {connection_code: ["environment_not_enabled"]}

      it "does not request /verify" do
        result
        expect(verify_request).not_to have_been_made
      end

      context "with a granted settlement holding the payment" do
        let(:customer) { create(:customer, organization:, x402_agent_address: payer_address) }
        let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{payer_address}_agent_api") }
        let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true) }
        let!(:settlement) do
          create(
            :x402_settlement, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
            purchase_settings: stored_settings, customer:, subscription:, wallet_transaction: create(:wallet_transaction, wallet:),
            request_key: idempotency_key
          )
        end

        it "answers from the row" do
          expect(result).to have_attributes(settlement:, replayed: true)
        end
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

    context "with the payer's subscription id held by another customer" do
      before { create(:subscription, customer: create(:customer, organization:), plan:, external_id: "x402_#{payer_address}_agent_api") }

      it_behaves_like "a refusal before settle", {base: ["subscription_external_id_taken"]}
    end

    context "with the payer at the wallet cap" do
      before do
        customer = create(:customer, organization:, x402_agent_address: payer_address, external_id: "x402_#{payer_address}")
        6.times { |index| create(:wallet, customer:, code: "other_credits_#{index}", currency: "USD") }
      end

      it_behaves_like "a refusal before settle", {base: ["wallet_limit_reached"]}
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

    context "with an exception raised inside the grant" do
      before do
        allow(Sentry).to receive(:capture_exception)
        allow(WalletTransactions::CreateService).to receive(:call!).and_raise(ActiveRecord::StatementInvalid)
      end

      it "fails with credit_grant_failed" do
        expect(result.error.messages).to eq(base: ["credit_grant_failed"])
      end

      it "keeps the settled row for a replay" do
        result
        expect(X402::Settlement.sole).to have_attributes(status: "settled", wallet_transaction_id: nil)
      end

      it "reports the exception" do
        result
        expect(Sentry).to have_received(:capture_exception).with(instance_of(ActiveRecord::StatementInvalid), extra: hash_including(:settlement_id))
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

    context "with a granted settlement holding the payment" do
      let(:customer) { create(:customer, organization:, x402_agent_address: payer_address) }
      let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{payer_address}_agent_api") }
      let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", x402_enabled: true) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:) }
      let!(:settlement) do
        create(
          :x402_settlement, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
          purchase_settings: stored_settings, customer:, subscription:, wallet_transaction:, request_key: idempotency_key
        )
      end

      it "answers from the row" do
        expect(result.settlement).to eq(settlement)
      end

      it "is a replay" do
        expect(result.replayed).to be(true)
      end

      it "calls no facilitator" do
        result
        expect(verify_request).not_to have_been_made
      end

      it "grants nothing" do
        expect { result }.not_to change(WalletTransaction, :count)
      end

      it "logs the replay" do
        result
        expect(Rails.logger).to have_received(:info).with("X402::CreditPurchases::PurchaseService replay status=settled settings_changed=false")
      end

      context "with other settings" do
        let(:params) { super().merge(plan_code: "other_plan", wallet_code: "other_wallet", connection_code: "unknown") }

        it "answers from the row" do
          expect(result.settlement).to eq(settlement)
        end

        it "logs the changed settings" do
          result
          expect(Rails.logger).to have_received(:info).with("X402::CreditPurchases::PurchaseService replay status=settled settings_changed=true")
        end
      end

      context "with its subscription terminated" do
        let(:subscription) { create(:subscription, :terminated, customer:, plan:, external_id: "x402_#{payer_address}_agent_api") }

        it "answers the grant's subscription" do
          expect(result.settlement.subscription.external_id).to eq("x402_#{payer_address}_agent_api")
        end
      end

      context "with a rebuilt envelope" do
        let(:payment) do
          authorization = x402_evm_payment.dig("payload", "authorization")
          {
            "extensions" => {"bazaar" => {}},
            "payload" => {
              "authorization" => authorization.merge("from" => authorization["from"].downcase, "to" => authorization["to"].downcase).to_a.reverse.to_h,
              "signature" => "0x#{"ef" * 65}"
            },
            "accepted" => x402_evm_requirements.to_a.reverse.to_h,
            "resource" => {"url" => "https://api.example.com/other"},
            "x402Version" => 2
          }
        end
        let(:payment_requirements) { x402_evm_requirements.merge("asset" => x402_evm_requirements["asset"].downcase).to_a.reverse.to_h }

        it "answers from the row" do
          expect(result.settlement).to eq(settlement)
        end
      end

      context "with the payout address rotated since" do
        let!(:settlement) do
          build(
            :x402_settlement, organization:, x402_connection:, payee_address: "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", payer_address:,
            payment_digest: digest, purchase_settings: stored_settings, customer:, subscription:, wallet_transaction:, request_key: idempotency_key
          ).tap { |row| row.save!(validate: false) }
        end

        it "answers from the row" do
          expect(result.settlement).to eq(settlement)
        end
      end

      context "when presented by another request" do
        let(:params) { super().merge(idempotency_key: other_key) }

        it_behaves_like "a replay refusal"

        it "logs the refusal" do
          result
          expect(Rails.logger).to have_received(:warn).with("X402::CreditPurchases::PurchaseService call failed reason=other_request network=eip155:84532")
        end

        context "with the payment rebuilt from the chain" do
          let(:payment) do
            {
              "x402Version" => 2,
              "resource" => {"url" => "https://api.example.com/other"},
              "accepted" => x402_evm_requirements,
              "payload" => x402_evm_payment["payload"]
            }
          end

          it_behaves_like "a replay refusal"
        end

        context "with a garbage signature" do
          let(:payment) { x402_evm_payment.deep_merge("payload" => {"signature" => "0xdeadbeef"}) }

          it_behaves_like "a replay refusal"
        end

        context "with another signature over the same authorization" do
          let(:payment) { x402_evm_payment.deep_merge("payload" => {"signature" => "0x#{"cd" * 65}"}) }

          it_behaves_like "a replay refusal"
        end

        context "with another connection" do
          let(:params) { super().merge(connection_code: create(:x402_connection, organization:).code) }

          it_behaves_like "a replay refusal"
        end
      end

      context "when presented without a key" do
        let(:params) { super().except(:idempotency_key) }

        it_behaves_like "a replay refusal"
      end
    end

    context "with a settled settlement without a grant" do
      before do
        create(
          :x402_settlement, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
          settled_amount_atomic: 10_000_000, settled_amount_cents: 1000, purchase_settings: stored_settings, request_key: idempotency_key
        )
      end

      it "grants from the row" do
        expect(result.settlement.reload.wallet_transaction).to be_present
      end

      it "is a replay" do
        expect(result.replayed).to be(true)
      end

      it "grants once" do
        expect { result }.to change(WalletTransaction, :count).by(1)
      end

      it "calls no facilitator" do
        result
        expect(settle_request).not_to have_been_made
      end

      context "with another plan in the request" do
        let(:params) { super().merge(plan_code: "other_plan") }

        it "grants on the stored plan" do
          expect(result.settlement.subscription.plan).to eq(plan)
        end
      end

      context "with a grant failing" do
        before { allow(X402::Subscriptions::ResolveService).to receive(:call!).and_raise(ActiveRecord::LockWaitTimeout) }

        it "fails with credit_grant_failed" do
          expect(result.error.messages).to eq(base: ["credit_grant_failed"])
        end
      end

      context "when presented by another request" do
        let(:params) { super().merge(idempotency_key: other_key) }

        it_behaves_like "a replay refusal"
      end
    end

    context "with a pending settlement holding the payment" do
      let!(:settlement) do
        create(
          :x402_settlement, :pending, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
          purchase_settings: stored_settings, request_key: idempotency_key
        )
      end

      it "answers the pending row" do
        expect(result.settlement).to have_attributes(id: settlement.id, status: "pending")
      end

      it "is a replay" do
        expect(result.replayed).to be(true)
      end

      it "calls no facilitator" do
        result
        expect(verify_request).not_to have_been_made
      end

      context "when presented by another request" do
        let(:params) { super().merge(idempotency_key: other_key) }

        it_behaves_like "a replay refusal"
      end
    end

    context "with a settlement made without a key holding the payment" do
      before do
        create(:x402_settlement, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest, purchase_settings: stored_settings)
      end

      it_behaves_like "a replay refusal"

      context "when presented without a key" do
        let(:params) { super().except(:idempotency_key) }

        it_behaves_like "a replay refusal"
      end
    end

    context "with an invoice payment holding the payment" do
      before do
        create(:x402_settlement, :invoice_payment, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest)
      end

      it_behaves_like "a replay refusal"

      it "logs the refusal" do
        result
        expect(Rails.logger).to have_received(:warn).with(a_string_including("reason=recorded_as_invoice_payment"))
      end
    end

    context "with a pending invoice payment holding the payment" do
      before { create(:x402_settlement, :pending, :invoice_payment, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest) }

      it_behaves_like "a replay refusal"
    end

    context "with a failed settlement holding the payment" do
      let!(:settlement) do
        create(:x402_settlement, :failed, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest, purchase_settings: stored_settings)
      end

      it "settles the payment again" do
        expect(result.settlement).to have_attributes(status: "settled", payment_digest: digest)
      end

      it "keeps the failed row" do
        expect(result.settlement.id).not_to eq(settlement.id)
      end
    end

    context "with another organization's settlement holding the payment" do
      before { create(:x402_settlement, payer_address:, payment_digest: digest) }

      it_behaves_like "a refusal before settle", {base: ["payment_already_recorded"]}
    end

    context "with the same payment inserted during /verify" do
      before do
        stub_request(:post, "#{cdp_facilitator_url}/verify").to_return do
          create(
            :x402_settlement, :pending, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
            purchase_settings: stored_settings, request_key: idempotency_key
          )
          {status: 200, body: cdp_fixture("verify_valid")}
        end
      end

      it "answers the winner's row" do
        expect(result.settlement).to have_attributes(payment_digest: digest, status: "pending")
      end

      it "is a replay" do
        expect(result.replayed).to be(true)
      end

      it "does not request /settle" do
        result
        expect(settle_request).not_to have_been_made
      end

      context "when another request inserted it" do
        before do
          stub_request(:post, "#{cdp_facilitator_url}/verify").to_return do
            create(
              :x402_settlement, :pending, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
              purchase_settings: stored_settings, request_key: other_key
            )
            {status: 200, body: cdp_fixture("verify_valid")}
          end
        end

        it "fails with payment_already_settled" do
          expect(result.error.messages).to eq(base: ["payment_already_settled"])
        end

        it "answers no settlement" do
          expect(result.settlement).to be_nil
        end

        it "does not request /settle" do
          result
          expect(settle_request).not_to have_been_made
        end
      end
    end

    context "with an invoice payment inserted during /verify" do
      before do
        stub_request(:post, "#{cdp_facilitator_url}/verify").to_return do
          create(:x402_settlement, :pending, :invoice_payment, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest)
          {status: 200, body: cdp_fixture("verify_valid")}
        end
      end

      it "fails with payment_already_settled" do
        expect(result.error.messages).to eq(base: ["payment_already_settled"])
      end

      it "does not request /settle" do
        result
        expect(settle_request).not_to have_been_made
      end
    end

    context "with a second first purchase while the first settles" do
      let(:second_payment) { x402_evm_payment.deep_merge("payload" => {"authorization" => {"nonce" => "0x#{"11" * 32}"}}) }
      let(:second_results) { [] }

      before do
        stub_request(:post, "#{cdp_facilitator_url}/settle").to_return do
          second_results << described_class.call(organization:, params: params.merge(payment: second_payment))
          {status: 200, body: cdp_fixture("settle_success")}
        end
      end

      it "refuses the second as pending" do
        result
        expect(second_results.sole.error.messages).to eq(base: ["credit_purchase_pending"])
      end

      it "settles the first" do
        expect(result.settlement.reload.status).to eq("settled")
      end

      it "requests /settle once" do
        result
        expect(settle_request).to have_been_made.once
      end
    end

    context "with an explicit settle mode" do
      let(:params) { super().merge(mode: "settle") }

      it "settles the purchase" do
        expect(result.settlement.reload).to have_attributes(status: "settled", settled_by: "lago", transaction_hash: settled_hash)
      end
    end

    context "with a null mode" do
      let(:params) { super().merge(mode: nil) }

      it "settles the purchase" do
        expect(result.settlement.reload).to have_attributes(status: "settled", settled_by: "lago")
      end
    end

    ["steal", 1, ["record"]].each do |unknown|
      context "with the mode #{unknown.inspect}" do
        let(:params) { super().merge(mode: unknown) }

        it_behaves_like "a refusal before settle", {mode: ["invalid_value"]}

        it "does not request /verify" do
          result
          expect(verify_request).not_to have_been_made
        end
      end
    end

    context "with a settle response in settle mode" do
      let(:params) { super().merge(settle_response: {"success" => true}) }

      it_behaves_like "a refusal before settle", {settle_response: ["not_allowed_in_settle_mode"]}
    end

    context "with a verify response in settle mode" do
      let(:params) { super().merge(verify_response: {"isValid" => true}) }

      it_behaves_like "a refusal before settle", {verify_response: ["not_allowed_in_settle_mode"]}
    end

    context "with the record mode" do
      let(:gate_hash) { "0x#{"ef" * 32}" }
      let(:settle_response) { {"success" => true, "transaction" => gate_hash, "network" => "eip155:84532", "payer" => payer_address} }
      let(:params) { super().merge(mode: "record", settle_response:) }

      shared_examples "a refused record" do |messages|
        it_behaves_like "a refusal before settle", messages

        it "calls no facilitator" do
          result
          expect(verify_request).not_to have_been_made
        end
      end

      context "with a first purchase" do
        it "records the gate's settlement" do
          expect(result.settlement.reload).to have_attributes(status: "settled", settled_by: "merchant", transaction_hash: gate_hash, payer_address:)
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

        it "stores the settings and the key's digest" do
          expect(result.settlement.reload).to have_attributes(purchase_settings: stored_settings, request_key_digest: OpenSSL::Digest::SHA256.hexdigest(idempotency_key))
        end

        it "calls no facilitator" do
          result
          expect(verify_request).not_to have_been_made
          expect(settle_request).not_to have_been_made
        end

        it "logs no refusal" do
          result
          expect(Rails.logger).not_to have_received(:warn)
        end
      end

      context "when the purchase is billed" do
        let(:invoice) { result.settlement.wallet_transaction.reload.invoice }

        before do
          result
          perform_all_enqueued_jobs(only: [BillPaidCreditJob, X402::CreditPurchases::CreatePaymentJob, Invoices::PrepaidCreditJob])
        end

        it "pays the credit invoice with one x402 payment" do
          expect(invoice).to have_attributes(invoice_type: "credit", payment_status: "succeeded", total_paid_amount_cents: 1000)
          expect(invoice.payments.sole).to have_attributes(payment_type: "x402", amount_cents: 1000)
          expect(result.settlement.reload.payment).to eq(invoice.payments.sole)
        end

        it "grants the credits once" do
          expect(result.settlement.wallet_transaction.wallet.reload).to have_attributes(balance_cents: 1000, credits_balance: BigDecimal("10000"))
          expect(WalletTransaction.count).to eq(1)
        end
      end

      context "with the gate's verify answer" do
        let(:params) { super().merge(verify_response: {"isValid" => true, "payer" => payer_address}) }

        it "keeps it with the settle response" do
          expect(result.settlement.reload.payload).to include("verify_response" => {"isValid" => true, "payer" => payer_address}, "settle_response" => settle_response)
        end
      end

      context "with a maxTimeoutSeconds of 300" do
        let(:payment_requirements) { x402_evm_requirements.merge("maxTimeoutSeconds" => 300) }

        it "records the purchase" do
          expect(result.settlement.reload).to have_attributes(status: "settled", settled_by: "merchant")
        end
      end

      context "with another purchase of the payer pending" do
        before { create(:x402_settlement, :pending, organization:, x402_connection:, payee_address:, payer_address:) }

        it "records the purchase" do
          expect(result.settlement.reload).to have_attributes(status: "settled", settled_by: "merchant")
        end

        it "grants the credits" do
          expect(result.settlement.wallet_transaction).to be_present
        end
      end

      context "without a settle response" do
        let(:params) { super().except(:settle_response) }

        it_behaves_like "a refused record", {settle_response: ["value_is_mandatory"]}
      end

      context "with a settle response that is not an object" do
        let(:settle_response) { "settled" }

        it_behaves_like "a refused record", {settle_response: ["invalid_settle_response"]}
      end

      context "with a verify answer that is not an object" do
        let(:params) { super().merge(verify_response: "valid") }

        it_behaves_like "a refused record", {verify_response: ["invalid_verify_response"]}
      end

      context "with an unsuccessful settle" do
        let(:settle_response) { {"success" => false, "errorReason" => "insufficient_funds", "network" => "eip155:84532", "transaction" => ""} }

        it_behaves_like "a refused record", {settle_response: ["settle_not_successful"]}

        it "logs the refusal" do
          result
          expect(Rails.logger).to have_received(:warn)
            .with("X402::CreditPurchases::PurchaseService call failed mode=record field=settle_response reason=settle_not_successful network=eip155:84532").once
        end
      end

      context "with a settle response for another payer" do
        let(:settle_response) { super().merge("payer" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") }

        it_behaves_like "a refused record", {settle_response: ["does_not_match_payment"]}
      end

      context "with an authorization value other than the amount" do
        let(:x402_evm_payment) { super().deep_merge("payload" => {"authorization" => {"value" => "10000001"}}) }

        it_behaves_like "a refused record", {payment: ["amount_mismatch"]}
      end

      context "with an unknown connection" do
        let(:params) { super().merge(connection_code: "unknown") }

        it "fails with not found" do
          expect(result.error.error_code).to eq("connection_not_found")
        end

        it "logs the refusal" do
          result
          expect(Rails.logger).to have_received(:warn)
            .with("X402::CreditPurchases::PurchaseService call failed mode=record field=base reason=connection_not_found network=eip155:84532")
        end
      end

      context "without plan and wallet codes" do
        let(:params) { super().except(:plan_code, :wallet_code) }

        it "logs one line per refusal" do
          result
          expect(Rails.logger).to have_received(:warn)
            .with("X402::CreditPurchases::PurchaseService call failed mode=record field=plan_code reason=value_is_mandatory network=eip155:84532").once
          expect(Rails.logger).to have_received(:warn)
            .with("X402::CreditPurchases::PurchaseService call failed mode=record field=wallet_code reason=value_is_mandatory network=eip155:84532").once
        end
      end

      context "with a network Lago does not settle on" do
        let(:payment_requirements) { x402_evm_requirements.merge("network" => "base-sepolia") }

        it_behaves_like "a refused record", {payment: ["unsupported_network"]}

        it "logs the refusal without the network" do
          result
          expect(Rails.logger).to have_received(:warn).with("X402::CreditPurchases::PurchaseService call failed mode=record field=payment reason=unsupported_network").once
        end
      end

      context "with an unknown payer and customer creation off" do
        let(:x402_connection) do
          create(
            :x402_connection,
            organization:,
            networks: ["eip155:84532"],
            payout_addresses: {"evm" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5"},
            auto_create_customers: false,
            cdp_api_key_id:,
            cdp_api_key_secret:
          )
        end

        it_behaves_like "a refused record", {base: ["buyer_not_recognized"]}
      end

      context "with an amount above the wallet shape's maximum" do
        let(:wallet_shape) { super().merge("paid_top_up_max_amount_cents" => "500") }

        it_behaves_like "a refused record", {payment_requirements: ["amount_above_maximum"]}
      end

      context "with a testnet connection on an organization running on mainnet" do
        let(:organization) { create(:organization, feature_flags: ["x402_mainnet"]) }
        let(:x402_connection) do
          create(
            :x402_connection,
            :saved_before_switch,
            organization:,
            networks: ["eip155:84532"],
            payout_addresses: {"evm" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5"},
            cdp_api_key_id:,
            cdp_api_key_secret:
          )
        end

        it_behaves_like "a refused record", {connection_code: ["environment_not_enabled"]}
      end

      context "with another payment holding the gate's transaction" do
        before { create(:x402_settlement, organization:, x402_connection:, payee_address:, transaction_hash: gate_hash) }

        it_behaves_like "a refused record", {settle_response: ["transaction_already_recorded"]}
      end

      context "with an invoice payment holding the payment" do
        before { create(:x402_settlement, :invoice_payment, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest) }

        it_behaves_like "a replay refusal"
      end

      context "with a pending settlement of this request holding the payment" do
        let!(:settlement) do
          create(
            :x402_settlement, :pending, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
            purchase_settings: stored_settings, request_key: idempotency_key
          )
        end

        it "answers the pending row" do
          expect(result.settlement).to have_attributes(id: settlement.id, status: "pending")
        end

        it "is a replay" do
          expect(result.replayed).to be(true)
        end
      end

      context "when the record is resent" do
        let!(:recorded) { described_class.call(organization:, params:).settlement }

        it "answers from the row" do
          expect(result.settlement).to eq(recorded)
        end

        it "is a replay" do
          expect(result.replayed).to be(true)
        end

        it "grants once" do
          result
          expect(WalletTransaction.count).to eq(1)
        end

        context "when resent in settle mode" do
          subject(:result) { described_class.call(organization:, params: params.except(:mode, :settle_response)) }

          it "answers from the row" do
            expect(result.settlement).to eq(recorded)
          end

          it "is a replay" do
            expect(result.replayed).to be(true)
          end

          it "calls no facilitator" do
            result
            expect(verify_request).not_to have_been_made
          end
        end

        context "when resent under another key" do
          subject(:result) { described_class.call(organization:, params: params.merge(idempotency_key: other_key)) }

          it_behaves_like "a replay refusal"
        end
      end

      context "with the same payment recorded while this one is checked" do
        let(:winner_hash) { gate_hash }

        before do
          allow(X402::Settlements::VerifyService).to receive(:call).and_wrap_original do |original, **arguments|
            original.call(**arguments).tap do
              create(
                :x402_settlement, :merchant, organization:, x402_connection:, payee_address:, payer_address:, payment_digest: digest,
                purchase_settings: stored_settings, request_key: idempotency_key, transaction_hash: winner_hash
              )
            end
          end
        end

        it "answers the winner's row" do
          expect(result.settlement).to have_attributes(payment_digest: digest, transaction_hash: winner_hash)
        end

        it "is a replay" do
          expect(result.replayed).to be(true)
        end

        it "writes no second row" do
          expect { result }.to change(X402::Settlement, :count).by(1)
        end

        context "with the winner holding another transaction" do
          let(:winner_hash) { "0x#{"12" * 32}" }

          it "answers the winner's row" do
            expect(result.settlement).to have_attributes(payment_digest: digest, transaction_hash: winner_hash)
          end

          it "is a replay" do
            expect(result.replayed).to be(true)
          end
        end
      end

      context "with a Solana payment" do
        let(:solana_transaction) do
          build_solana_transaction(
            keys: [
              "D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM", x402_svm_payer, "6TWy94HPrwQxtNBjPAzJUBizBUmmtd1Q6bh9TUwa21S5",
              "H6KPkFCgvBzk6uCcD3VmQKZdp2BTkcoCctcgziSLeSpL", "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU", SolanaTransactionBuilder::TOKEN_PROGRAM
            ],
            instructions: [{program: 5, accounts: [2, 4, 3, 1], data: transfer_checked_data(10_000_000)}],
            signatures: ["\x00".b * 64, "\x02".b * 64]
          )
        end
        let(:x402_svm_requirements) { super().merge("amount" => "10000000") }
        let(:payment) { x402_svm_payment.deep_merge("payload" => {"transaction" => Base64.strict_encode64(solana_transaction)}) }
        let(:payment_requirements) { x402_svm_requirements }
        let(:signature) { X402::Base58.encode("\x01".b * 64) }
        let(:settle_response) { {"success" => true, "transaction" => signature, "network" => x402_svm_requirements["network"]} }

        it "records the gate's settlement" do
          expect(result.settlement.reload).to have_attributes(status: "settled", settled_by: "merchant", transaction_hash: signature, payer_address: x402_svm_payer)
        end

        it "grants the payer the transaction carries" do
          expect(result.settlement.customer).to have_attributes(x402_agent_address: x402_svm_payer)
        end

        context "with a settle response for another payer" do
          let(:settle_response) { super().merge("payer" => "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG") }

          it_behaves_like "a refused record", {settle_response: ["does_not_match_payment"]}
        end
      end
    end
  end
end
