# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::VoidService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) do
    create(
      :wallet,
      customer:,
      balance_cents: 1000,
      credits_balance: 10.0,
      ongoing_balance_cents: 1000,
      credits_ongoing_balance: 10.0,
      traceable: false
    )
  end
  let(:credit_amount) { BigDecimal("10.00") }
  let(:wallet_credit) { WalletCredit.new(wallet:, credit_amount:) }

  before do
    subscription
  end

  describe "#call" do
    subject(:result) { described_class.call(wallet:, wallet_credit:, **args) }

    let(:args) { {} }

    context "when credits amount is zero" do
      let(:credit_amount) { BigDecimal("0.00") }

      it "does not create a wallet transaction" do
        expect { subject }.not_to change(WalletTransaction, :count)
      end
    end

    context "with minimum arguments" do
      it "creates a wallet transaction" do
        expect { subject }.to change(WalletTransaction, :count).by(1)
      end

      it "sets default values" do
        freeze_time do
          expect(result.wallet_transaction)
            .to be_a(WalletTransaction)
            .and be_persisted
            .and have_attributes(
              amount: 10,
              credit_amount: 10,
              transaction_type: "outbound",
              status: "settled",
              transaction_status: "voided",
              settled_at: Time.current,
              source: "manual",
              metadata: [],
              priority: 50,
              credit_note_id: nil,
              name: nil
            )
        end
      end

      it "updates wallet balance" do
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance_cents).to eq(0)
        expect(wallet.credits_balance).to eq(0.0)
      end
    end

    context "with all arguments" do
      let(:metadata) { [{"key" => "valid_value", "value" => "also_valid"}] }
      let(:credit_note_id) { create(:credit_note, organization:).id }

      let(:args) do
        {
          metadata:,
          credit_note_id:,
          source: :threshold,
          priority: 25,
          name: "Void Transaction"
        }
      end

      it "creates a wallet transaction" do
        expect { subject }.to change(WalletTransaction, :count).by(1)
      end

      it "sets all attributes" do
        freeze_time do
          expect(result.wallet_transaction)
            .to be_a(WalletTransaction)
            .and be_persisted
            .and have_attributes(
              amount: 10,
              credit_amount: 10,
              transaction_type: "outbound",
              status: "settled",
              transaction_status: "voided",
              settled_at: Time.current,
              metadata:,
              credit_note_id:,
              source: "threshold",
              priority: 25,
              name: "Void Transaction"
            )
        end
      end

      it "updates wallet balance" do
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance_cents).to eq(0)
        expect(wallet.credits_balance).to eq(0.0)
      end
    end

    context "with nil name" do
      let(:args) { {name: nil} }

      it "creates a wallet transaction with nil name" do
        expect(result.wallet_transaction.name).to be_nil
      end
    end

    context "when wallet is traceable" do
      let(:wallet) do
        create(
          :wallet,
          customer:,
          balance_cents: 1000,
          credits_balance: 10.0,
          ongoing_balance_cents: 1000,
          credits_ongoing_balance: 10.0,
          traceable: true
        )
      end

      let(:inbound_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :purchased,
          status: :settled,
          amount: 10,
          credit_amount: 10,
          remaining_amount_cents: 1000)
      end

      before do
        inbound_transaction
      end

      it "creates wallet transaction consumption records" do
        expect { subject }.to change(WalletTransactionConsumption, :count).by(1)

        expect(WalletTransactionConsumption.last).to have_attributes(
          inbound_wallet_transaction_id: inbound_transaction.id,
          outbound_wallet_transaction_id: result.wallet_transaction.id,
          consumed_amount_cents: 1000
        )

        expect(inbound_transaction.reload.remaining_amount_cents).to eq(0)
      end
    end

    context "when wallet is not traceable" do
      let(:wallet) do
        create(
          :wallet,
          customer:,
          balance_cents: 1000,
          credits_balance: 10.0,
          ongoing_balance_cents: 1000,
          credits_ongoing_balance: 10.0,
          traceable: false
        )
      end

      it "does not create wallet transaction consumption records" do
        expect { subject }.not_to change(WalletTransactionConsumption, :count)
      end
    end
  end
end
