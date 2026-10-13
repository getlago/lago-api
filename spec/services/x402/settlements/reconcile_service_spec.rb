# frozen_string_literal: true

require "rails_helper"

describe X402::Settlements::ReconcileService do
  subject(:result) { described_class.call(settlement:) }

  include_context "with an x402 payment"

  let(:payload) { {"payment" => x402_evm_payment, "payment_requirements" => x402_evm_requirements} }
  let(:settlement) { create(:x402_settlement, :pending, reconcile_after: 1.minute.ago, error_reason: "no_response", payload:) }
  let(:chain_hash) { "0x#{"ef" * 32}" }
  let(:reader) { instance_double(X402::Chain::EvmReader, settled?: true, identifier: chain_hash, final?: true) }

  before do
    allow(X402::Chain::EvmReader).to receive(:new).and_return(reader)
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

    context "with the hash of a settlement_pending answer" do
      let(:settlement) do
        create(
          :x402_settlement, :pending,
          reconcile_after: 1.minute.ago, error_reason: "settlement_pending", transaction_hash: "0x#{"cd" * 32}", payload:
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
          x402_connection: create(:x402_connection, :discarded), reconcile_after: 1.minute.ago, payload:
        )
      end

      it "marks the row settled" do
        expect(result.settlement.reload).to be_settled
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
    let(:settlement) { create(:x402_settlement, :solana, :pending, reconcile_after: 1.minute.ago, payload:) }
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
  end

  context "with a resolved row" do
    let(:settlement) { create(:x402_settlement, reconcile_after: 1.minute.ago) }

    it "does not read the chain" do
      result

      expect(X402::Chain::EvmReader).not_to have_received(:new)
    end
  end

  context "when the row was resolved after it was loaded" do
    let(:resolved) { create(:x402_settlement, transaction_hash: "0x#{"aa" * 32}") }
    let(:settlement) do
      X402::Settlement.instantiate(X402::Settlement.find(resolved.id).attributes_before_type_cast.merge("status" => "pending"))
    end

    it "leaves the row as the other caller wrote it" do
      result

      expect(resolved.reload).to have_attributes(status: "settled", transaction_hash: "0x#{"aa" * 32}")
    end
  end

  context "when called inside a transaction" do
    subject(:result) { ApplicationRecord.transaction { described_class.call(settlement:) } }

    it "refuses to run" do
      expect { result }.to raise_error(RuntimeError, /must run outside a database transaction/)
    end
  end
end
