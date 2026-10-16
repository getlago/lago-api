# frozen_string_literal: true

require "rails_helper"

describe X402::Settlements::ReconcileService do
  subject(:result) { described_class.call(settlement:) }

  include_context "with an x402 payment"

  let(:x402_connection) { create(:x402_connection, organization: create(:organization, feature_flags: ["x402_payments"])) }
  let(:plan) { create(:plan, organization: x402_connection.organization, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
  let(:purchase_settings) do
    {
      "plan_code" => "agent_api",
      "wallet_code" => "agent_credits",
      "wallet" => {"name" => "Agent credits", "rate_amount" => "1", "currency" => "USD"}
    }
  end
  let(:payload) { {"payment" => x402_evm_payment, "payment_requirements" => x402_evm_requirements} }
  let(:settlement) do
    create(:x402_settlement, :pending, x402_connection:, reconcile_after: 1.minute.ago, error_reason: "no_response", payload:, purchase_settings:)
  end
  let(:chain_hash) { "0x#{"ef" * 32}" }
  let(:reader) { instance_double(X402::Chain::EvmReader, settled?: true, identifier: chain_hash, final?: true) }

  before do
    plan
    allow(X402::Chain::EvmReader).to receive(:new).and_return(reader)
    allow(X402::CreditPurchases::GrantService).to receive(:call).and_call_original
    allow(Sentry).to receive(:capture_exception)
    allow(Sentry).to receive(:capture_message)
    allow(Rails.logger).to receive(:warn)
  end

  context "when the payment landed" do
    it "marks the row settled" do
      expect(result.settlement.reload).to be_settled
    end

    it "records the chain's transaction" do
      expect(result.settlement.reload.transaction_hash).to eq(chain_hash)
    end

    it "reads the chain from the stored payment" do
      result

      expect(X402::Chain::EvmReader).to have_received(:new).with(
        network: "eip155:84532",
        payment: x402_evm_payment,
        payment_requirements: x402_evm_requirements,
        since: settlement.created_at
      )
    end

    it "grants the credits" do
      expect(result.settlement.reload.wallet_transaction).to have_attributes(
        source: "x402", transaction_status: "purchased", status: "settled", credit_amount: BigDecimal("1"), amount: BigDecimal("1")
      )
    end

    it "links the agent onto the row" do
      expect(result.settlement.reload).to have_attributes(customer: be_present, subscription: be_present)
    end

    it "bills the purchase" do
      expect { result }.to have_enqueued_job(BillPaidCreditJob).with(instance_of(WalletTransaction), instance_of(Integer))
    end

    it "does not report" do
      result

      expect(Sentry).not_to have_received(:capture_exception)
    end

    context "without the x402 feature flag" do
      let(:x402_connection) { create(:x402_connection, organization: create(:organization, feature_flags: [])) }

      it "grants the credits" do
        expect(result.settlement.reload.wallet_transaction).to be_present
      end
    end

    context "with an invoice payment" do
      let(:invoice) { create(:invoice, organization: x402_connection.organization, currency: "USD", total_amount_cents: 100) }
      let(:settlement) do
        create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:, reconcile_after: 1.minute.ago, payload:)
      end

      it "marks the row settled" do
        expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: chain_hash)
      end

      it "grants nothing" do
        result

        expect(X402::CreditPurchases::GrantService).not_to have_received(:call)
      end

      it "records the payment" do
        expect(result.settlement.reload.payment).to have_attributes(payment_type: "x402", amount_cents: 100, payable: invoice)
      end

      it "marks the invoice paid" do
        result

        expect(invoice.reload.payment_status).to eq("succeeded")
      end

      context "when the payment cannot be recorded" do
        let(:invoice) { create(:invoice, organization: x402_connection.organization, currency: "USD", total_amount_cents: 50) }

        it "keeps the row settled" do
          expect(result.settlement.reload).to have_attributes(status: "settled", payment_id: nil)
        end

        it "reports the failure" do
          result

          expect(Sentry).to have_received(:capture_exception).with(instance_of(BaseService::ValidationFailure), extra: hash_including(settlement_id: settlement.id))
        end
      end

      context "with the transaction held by another row" do
        before { create(:x402_settlement, transaction_hash: chain_hash) }

        it "marks the row failed" do
          expect(result.settlement.reload).to have_attributes(status: "failed", error_reason: "transaction_already_recorded")
        end

        it "leaves the invoice alone" do
          result

          expect(invoice.reload.payment_status).to eq("pending")
        end
      end
    end

    context "when the grant fails" do
      let(:purchase_settings) do
        {
          "plan_code" => "unknown_plan",
          "wallet_code" => "agent_credits",
          "wallet" => {"name" => "Agent credits", "rate_amount" => "1", "currency" => "USD"}
        }
      end

      it "keeps the row settled without a grant" do
        expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: chain_hash, wallet_transaction_id: nil)
      end

      it "succeeds" do
        expect(result).to be_success
      end

      it "reports the failure" do
        result

        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(BaseService::NotFoundFailure),
          extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, network: "eip155:84532"}
        )
      end

      it "logs the failure" do
        result

        expect(Rails.logger).to have_received(:warn).with(
          "[x402] credit grant failed settlement_id=#{settlement.id} network=eip155:84532: BaseService::NotFoundFailure plan_not_found"
        )
      end
    end

    context "when the grant raises" do
      before { allow(X402::CreditPurchases::GrantService).to receive(:call).and_raise(RuntimeError, "boom") }

      it "keeps the row settled without a grant" do
        expect(result.settlement.reload).to have_attributes(status: "settled", wallet_transaction_id: nil)
      end

      it "reports the error" do
        result

        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(RuntimeError), extra: hash_including(settlement_id: settlement.id))
      end
    end

    context "with the hash of a settlement_pending answer" do
      let(:settlement) do
        create(
          :x402_settlement, :pending,
          x402_connection:, reconcile_after: 1.minute.ago, error_reason: "settlement_pending", transaction_hash: "0x#{"cd" * 32}",
          payload:, purchase_settings:
        )
      end

      it "records the chain's transaction instead" do
        expect(result.settlement.reload.transaction_hash).to eq(chain_hash)
      end
    end

    context "with the transaction held by another row" do
      let(:holder) { create(:x402_settlement, transaction_hash: chain_hash) }

      before { holder }

      it "marks the row failed" do
        expect(result.settlement.reload).to be_failed
      end

      it "names the shared transaction as the reason" do
        expect(result.settlement.reload.error_reason).to eq("transaction_already_recorded")
      end

      it "stores no transaction on the row" do
        expect(result.settlement.reload.transaction_hash).to be_nil
      end

      it "leaves the other row as it was" do
        result

        expect(holder.reload).to have_attributes(status: "settled", transaction_hash: chain_hash)
      end

      it "grants nothing" do
        result

        expect(X402::CreditPurchases::GrantService).not_to have_received(:call)
      end

      it "logs the shared transaction" do
        result

        expect(Rails.logger).to have_received(:warn).with(
          "[x402] transaction already recorded settlement_id=#{settlement.id} holder_id=#{holder.id} network=eip155:84532"
        )
      end

      context "with the hash of a settlement_pending answer" do
        let(:settlement) do
          create(
            :x402_settlement, :pending,
            reconcile_after: 1.minute.ago, error_reason: "settlement_pending", transaction_hash: "0x#{"cd" * 32}", payload:
          )
        end

        it "clears the unconfirmed transaction" do
          expect(result.settlement.reload.transaction_hash).to be_nil
        end
      end

      context "when that row is still pending" do
        let(:holder_payload) do
          {"payment" => x402_evm_payment.deep_merge("payload" => {"authorization" => {"value" => "2000"}}), "payment_requirements" => x402_evm_requirements}
        end
        let(:holder) { create(:x402_settlement, :pending, transaction_hash: chain_hash, payload: holder_payload) }

        it "leaves the row as it was" do
          expect(result.settlement.reload).to have_attributes(status: "pending", transaction_hash: nil, error_reason: "no_response")
        end

        it "does not report" do
          result

          expect(Sentry).not_to have_received(:capture_message)
          expect(Sentry).not_to have_received(:capture_exception)
        end

        context "when the chain refutes that row's claim" do
          let(:holder_reader) { instance_double(X402::Chain::EvmReader, settled?: false, identifier: nil, final?: true) }

          before do
            allow(X402::Chain::EvmReader).to receive(:new).with(hash_including(payment: holder_payload["payment"])).and_return(holder_reader)
            described_class.call(settlement: holder)
          end

          it "fails that row without the transaction" do
            expect(holder.reload).to have_attributes(status: "failed", transaction_hash: nil)
          end

          it "settles the row with the transaction" do
            expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash: chain_hash)
          end

          it "grants the row once" do
            expect(result.settlement.reload.wallet_transaction).to be_present
            expect(X402::CreditPurchases::GrantService).to have_received(:call).once
          end
        end
      end

      context "when that row failed" do
        let(:holder) { create(:x402_settlement, :failed, transaction_hash: chain_hash) }

        it "leaves the row as it was" do
          expect(result.settlement.reload).to have_attributes(status: "pending", transaction_hash: nil, error_reason: "no_response")
        end

        it "reports the held transaction" do
          result

          expect(Sentry).to have_received(:capture_message).with(
            "[x402] transaction held by a failed settlement",
            extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, holder_id: holder.id, network: "eip155:84532"}
          )
        end
      end
    end

    context "when another unique index refuses the write" do
      before do
        allow(settlement).to receive(:update!).and_raise(
          ActiveRecord::RecordNotUnique, 'PG::UniqueViolation: ERROR:  duplicate key value violates unique constraint "index_x402_settlements_on_payment_digest"'
        )
      end

      it "raises the error" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_settlements_on_payment_digest/)
      end
    end

    context "with a deleted connection" do
      let(:settlement) do
        create(
          :x402_settlement, :pending,
          x402_connection: create(:x402_connection, :discarded, organization: x402_connection.organization),
          reconcile_after: 1.minute.ago, payload:, purchase_settings:
        )
      end

      it "marks the row settled" do
        expect(result.settlement.reload).to be_settled
      end

      it "grants the credits" do
        expect(result.settlement.reload.wallet_transaction).to be_present
      end
    end

    context "with a testnet connection on an organization running on mainnet" do
      let(:x402_connection) do
        create(:x402_connection, :saved_before_switch, organization: create(:organization, feature_flags: ["x402_payments", "x402_mainnet"]))
      end

      it "marks the row settled" do
        expect(result.settlement.reload).to be_settled
      end

      it "grants the credits" do
        expect(result.settlement.reload.wallet_transaction).to be_present
      end
    end
  end

  context "when nothing landed" do
    let(:reader) { instance_double(X402::Chain::EvmReader, settled?: false, identifier: nil, final?: true) }

    it "marks the row failed" do
      expect(result.settlement.reload).to be_failed
    end

    it "keeps the settle's reason" do
      expect(result.settlement.reload.error_reason).to eq("no_response")
    end

    context "with an invoice payment" do
      let(:invoice) { create(:invoice, organization: x402_connection.organization, currency: "USD", total_amount_cents: 100) }
      let(:settlement) do
        create(
          :x402_settlement, :pending, :invoice_payment,
          x402_connection:, invoice:, reconcile_after: 1.minute.ago, error_reason: "no_response", payload:
        )
      end

      it "marks the row failed" do
        expect(result.settlement.reload).to be_failed
      end

      it "marks the invoice payment failed" do
        result

        expect(invoice.reload.payment_status).to eq("failed")
      end

      it "notifies the merchant" do
        expect { result }.to have_enqueued_job(SendWebhookJob).with("invoice.payment_status_updated", invoice)
      end

      context "with an invoice paid meanwhile" do
        let(:invoice) do
          create(:invoice, organization: x402_connection.organization, currency: "USD", total_amount_cents: 100, payment_status: "succeeded")
        end

        it "leaves the invoice paid" do
          result

          expect(invoice.reload.payment_status).to eq("succeeded")
        end

        it "sends no webhook" do
          expect { result }.not_to have_enqueued_job(SendWebhookJob).with("invoice.payment_status_updated", invoice)
        end
      end

      context "with a voided invoice" do
        let(:invoice) { create(:invoice, :voided, organization: x402_connection.organization, currency: "USD", total_amount_cents: 100) }

        it "marks the row failed" do
          expect(result.settlement.reload).to be_failed
        end

        it "leaves the invoice as it was" do
          expect { result }.not_to change { invoice.reload.attributes.slice("status", "payment_status") }
        end
      end

      context "when the chain can still change its answer" do
        let(:reader) { instance_double(X402::Chain::EvmReader, settled?: false, identifier: nil, final?: false) }

        it "leaves the invoice pending" do
          result

          expect(invoice.reload.payment_status).to eq("pending")
        end
      end
    end

    context "with the hash of a settlement_pending answer" do
      let(:settlement) do
        create(
          :x402_settlement, :pending,
          reconcile_after: 1.minute.ago, error_reason: "settlement_pending", transaction_hash: "0x#{"cd" * 32}", payload:
        )
      end

      it "clears the unconfirmed transaction" do
        expect(result.settlement.reload.transaction_hash).to be_nil
      end
    end

    context "when the chain can still change its answer" do
      let(:reader) { instance_double(X402::Chain::EvmReader, settled?: false, identifier: nil, final?: false) }

      it "leaves the row pending" do
        expect(result.settlement.reload).to be_pending
      end

      it "does not report" do
        result

        expect(Sentry).not_to have_received(:capture_exception)
      end
    end

    context "when the finality read fails" do
      before { allow(reader).to receive(:final?).and_raise(X402::Chain::InconclusiveError, "isBlockhashValid returned no usable answer") }

      it "leaves the row pending" do
        expect(result.settlement.reload).to be_pending
      end

      it "reports the failure" do
        result

        expect(Sentry).to have_received(:capture_exception).with(an_instance_of(X402::Chain::InconclusiveError), extra: hash_including(settlement_id: settlement.id))
      end
    end
  end

  [X402::Chain::UnreachableError, X402::Chain::UnreadablePaymentError, X402::Chain::InconclusiveError].each do |error_class|
    context "when the chain read raises #{error_class.name.demodulize}" do
      before { allow(reader).to receive(:settled?).and_raise(error_class, "eth_call: HTTP 503") }

      it "leaves the row pending" do
        expect(result.settlement.reload).to be_pending
      end

      it "reports the failure" do
        result

        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(error_class),
          extra: {organization_id: settlement.organization_id, settlement_id: settlement.id, network: "eip155:84532"}
        )
      end

      it "logs the failure" do
        result

        expect(Rails.logger).to have_received(:warn).with(
          "[x402] chain read failed settlement_id=#{settlement.id} network=eip155:84532: #{error_class.name} eth_call: HTTP 503"
        )
      end
    end
  end

  context "with a Solana row" do
    let(:signature) { X402::Base58.encode("\x01".b * 64) }
    let(:payload) { {"payment" => x402_svm_payment, "payment_requirements" => x402_svm_requirements} }
    let(:settlement) do
      create(
        :x402_settlement, :solana, :pending,
        x402_connection: create(:x402_connection, :solana, organization: x402_connection.organization),
        reconcile_after: 1.minute.ago, payload:, purchase_settings:
      )
    end
    let(:svm_reader) { instance_double(X402::Chain::SvmReader, settled?: true, identifier: signature, final?: true) }

    before { allow(X402::Chain::SvmReader).to receive(:new).and_return(svm_reader) }

    it "reads the Solana chain from the stored payment" do
      result

      expect(X402::Chain::SvmReader).to have_received(:new).with(
        network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1",
        payment: x402_svm_payment,
        payment_requirements: x402_svm_requirements,
        since: settlement.created_at
      )
    end

    it "records the matched signature" do
      expect(result.settlement.reload.transaction_hash).to eq(signature)
    end

    it "grants the credits" do
      expect(result.settlement.reload.wallet_transaction).to be_present
    end
  end

  context "with a resolved row" do
    let(:settlement) { create(:x402_settlement, :failed, reconcile_after: 1.minute.ago) }

    it "does not read the chain" do
      result

      expect(X402::Chain::EvmReader).not_to have_received(:new)
    end
  end

  context "with a settled purchase awaiting its grant" do
    let(:settlement) { create(:x402_settlement, x402_connection:, purchase_settings:, transaction_hash: chain_hash, updated_at: 3.minutes.ago) }

    it "grants the credits" do
      expect(result.settlement.reload.wallet_transaction).to have_attributes(source: "x402", status: "settled")
    end

    it "does not read the chain" do
      result

      expect(X402::Chain::EvmReader).not_to have_received(:new)
    end

    context "with a purchase recorded by the merchant" do
      let(:settlement) { create(:x402_settlement, :merchant, x402_connection:, purchase_settings:) }

      it "grants the credits" do
        expect(result.settlement.reload.wallet_transaction).to be_present
      end
    end

    context "when another caller granted it after it was loaded" do
      let(:customer) { create(:customer, organization: x402_connection.organization) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet: create(:wallet, customer:)) }
      let(:granted) do
        create(
          :x402_settlement,
          x402_connection:, purchase_settings:, customer:, wallet_transaction:, subscription: create(:subscription, customer:, plan:)
        )
      end
      let(:settlement) do
        X402::Settlement.instantiate(X402::Settlement.find(granted.id).attributes_before_type_cast.merge("wallet_transaction_id" => nil))
      end

      before { settlement }

      it "grants nothing more" do
        expect { result }.not_to change(WalletTransaction, :count)
      end

      it "does not bill again" do
        expect { result }.not_to have_enqueued_job(BillPaidCreditJob)
      end

      it "keeps the first grant" do
        result

        expect(granted.reload.wallet_transaction).to eq(wallet_transaction)
      end
    end

    context "when the grant fails" do
      let(:purchase_settings) do
        {
          "plan_code" => "unknown_plan",
          "wallet_code" => "agent_credits",
          "wallet" => {"name" => "Agent credits", "rate_amount" => "1", "currency" => "USD"}
        }
      end

      it "succeeds" do
        expect(result).to be_success
      end

      it "keeps the row due for another attempt" do
        result

        expect(X402::Settlement.grant_retry_due).to eq([settlement])
      end
    end

    context "when the grant raises" do
      before { allow(X402::CreditPurchases::GrantService).to receive(:call).and_raise(RuntimeError, "boom") }

      it "keeps the row due for another attempt" do
        result

        expect(X402::Settlement.grant_retry_due).to eq([settlement])
      end

      it "logs the failure" do
        result

        expect(Rails.logger).to have_received(:warn).with(
          "[x402] credit grant failed settlement_id=#{settlement.id} network=eip155:84532: RuntimeError boom"
        )
      end
    end

    context "when jobs cannot be enqueued" do
      before { allow(ActiveJob::Base.queue_adapter).to receive(:enqueue).and_raise(RedisClient::CannotConnectError, "unreachable") }

      it "keeps the grant" do
        expect(result.settlement.reload.wallet_transaction).to be_present
      end

      it "logs a follow-up failure" do
        result

        expect(Rails.logger).to have_received(:warn).with(
          "[x402] credit grant follow-up failed settlement_id=#{settlement.id} network=eip155:84532: RedisClient::CannotConnectError unreachable"
        )
      end
    end

    context "when saving the grant raises" do
      before { allow(settlement).to receive(:save!).and_raise(ActiveRecord::RecordInvalid) }

      it "returns the row as stored" do
        expect(result.settlement).to have_attributes(customer_id: nil, subscription_id: nil, wallet_transaction_id: nil)
      end
    end
  end

  context "with a granted purchase" do
    let(:customer) { create(:customer, organization: x402_connection.organization) }
    let(:settlement) do
      create(
        :x402_settlement,
        x402_connection:, purchase_settings:, customer:,
        wallet_transaction: create(:wallet_transaction, wallet: create(:wallet, customer:)),
        subscription: create(:subscription, customer:, plan:)
      )
    end

    it "does not grant again" do
      result

      expect(X402::CreditPurchases::GrantService).not_to have_received(:call)
    end
  end

  context "with a settled invoice payment" do
    let(:invoice) { create(:invoice, organization: x402_connection.organization, currency: "USD", total_amount_cents: 100) }
    let(:settlement) { create(:x402_settlement, :invoice_payment, x402_connection:, invoice:) }

    it "grants nothing" do
      result

      expect(X402::CreditPurchases::GrantService).not_to have_received(:call)
    end

    it "records the payment" do
      expect(result.settlement.reload.payment).to be_present
    end

    it "keeps the row's transaction" do
      expect { result }.not_to change { settlement.reload.transaction_hash }
    end

    context "with a recorded payment" do
      let(:settlement) do
        create(:x402_settlement, :invoice_payment, x402_connection:, invoice:, payment: create(:payment, payable: invoice))
      end

      before { settlement }

      it "records nothing more" do
        expect { result }.not_to change(Payment, :count)
      end
    end
  end

  context "with a failed purchase" do
    let(:settlement) { create(:x402_settlement, :failed, x402_connection:, purchase_settings:) }

    it "grants nothing" do
      result

      expect(X402::CreditPurchases::GrantService).not_to have_received(:call)
    end
  end

  context "when the row was resolved after it was loaded" do
    let(:customer) { create(:customer, organization: x402_connection.organization) }
    let(:wallet_transaction) { create(:wallet_transaction, wallet: create(:wallet, customer:)) }
    let(:resolved) do
      create(
        :x402_settlement,
        x402_connection:, purchase_settings:, customer:, wallet_transaction:,
        subscription: create(:subscription, customer:, plan:), transaction_hash: "0x#{"aa" * 32}"
      )
    end
    let(:settlement) do
      X402::Settlement.instantiate(X402::Settlement.find(resolved.id).attributes_before_type_cast.merge("status" => "pending"))
    end

    before { settlement }

    it "leaves the row as the other caller wrote it" do
      result

      expect(resolved.reload).to have_attributes(status: "settled", transaction_hash: "0x#{"aa" * 32}")
    end

    it "grants nothing more" do
      expect { result }.not_to change(WalletTransaction, :count)
    end
  end

  context "when called inside a transaction" do
    subject(:result) { ApplicationRecord.transaction { described_class.call(settlement:) } }

    it "refuses to run" do
      expect { result }.to raise_error(RuntimeError, /must run outside a database transaction/)
    end
  end
end
