# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::TrackConsumptionService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:, organization:, balance_cents: 10000, credits_balance: 100.0) }

  describe "#call" do
    subject(:result) { described_class.call(outbound_wallet_transaction:) }

    context "when consuming by priority" do
      let!(:inbound_granted) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :granted,
          status: :settled,
          amount: 30,
          credit_amount: 30,
          remaining_amount_cents: 3000,
          priority: 10)
      end

      let!(:inbound_purchased) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :purchased,
          status: :settled,
          amount: 70,
          credit_amount: 70,
          remaining_amount_cents: 7000,
          priority: 10)
      end

      let(:outbound_wallet_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :outbound,
          transaction_status: :invoiced,
          status: :settled,
          amount: 50,
          credit_amount: 50)
      end

      it "creates consumption records following granted-first priority" do
        expect { result }.to change(WalletTransactionConsumption, :count).by(2)
      end

      it "consumes granted credits first" do
        result

        consumptions = outbound_wallet_transaction.fundings.order(:consumed_amount_cents)
        expect(consumptions.first.inbound_wallet_transaction).to eq(inbound_purchased)
        expect(consumptions.first.consumed_amount_cents).to eq(2000)

        expect(consumptions.second.inbound_wallet_transaction).to eq(inbound_granted)
        expect(consumptions.second.consumed_amount_cents).to eq(3000)
      end

      it "decrements remaining_amount_cents on inbound transactions" do
        result

        expect(inbound_granted.reload.remaining_amount_cents).to eq(0)
        expect(inbound_purchased.reload.remaining_amount_cents).to eq(5000)
      end

      it "returns a success result" do
        expect(result).to be_success
      end
    end

    context "when outbound amount exceeds available inbound amount" do
      let(:inbound_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :purchased,
          status: :settled,
          amount: 30,
          credit_amount: 30,
          remaining_amount_cents: 3000)
      end

      let(:outbound_wallet_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :outbound,
          transaction_status: :invoiced,
          status: :settled,
          amount: 50,
          credit_amount: 50)
      end

      before do
        inbound_transaction
      end

      it "does not create consumption records" do
        expect { result }.not_to change(WalletTransactionConsumption, :count)
      end

      it "returns a failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:amount_cents]).to eq(["exceeds_available_amount"])
      end
    end

    context "with multiple inbound transactions of different priorities" do
      let!(:inbound_low_priority) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :granted,
          status: :settled,
          amount: 50,
          credit_amount: 50,
          remaining_amount_cents: 5000,
          priority: 20,
          created_at: 2.days.ago)
      end

      let!(:inbound_high_priority) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :granted,
          status: :settled,
          amount: 50,
          credit_amount: 50,
          remaining_amount_cents: 5000,
          priority: 10,
          created_at: 1.day.ago)
      end

      let(:outbound_wallet_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :outbound,
          transaction_status: :invoiced,
          status: :settled,
          amount: 60,
          credit_amount: 60)
      end

      it "consumes from higher priority (lower number) first" do
        result

        expect(inbound_high_priority.reload.remaining_amount_cents).to eq(0)
        expect(inbound_low_priority.reload.remaining_amount_cents).to eq(4000)
      end
    end

    context "with inbound transactions of same priority but different created_at" do
      let!(:inbound_older) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :granted,
          status: :settled,
          amount: 50,
          credit_amount: 50,
          remaining_amount_cents: 5000,
          priority: 10,
          created_at: 2.days.ago)
      end

      let!(:inbound_newer) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :granted,
          status: :settled,
          amount: 50,
          credit_amount: 50,
          remaining_amount_cents: 5000,
          priority: 10,
          created_at: 1.day.ago)
      end

      let(:outbound_wallet_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :outbound,
          transaction_status: :invoiced,
          status: :settled,
          amount: 60,
          credit_amount: 60)
      end

      it "consumes from older transactions first (FIFO)" do
        result

        expect(inbound_older.reload.remaining_amount_cents).to eq(0)
        expect(inbound_newer.reload.remaining_amount_cents).to eq(4000)
      end
    end

    context "when no inbound transactions with remaining balance exist" do
      let(:outbound_wallet_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :outbound,
          transaction_status: :invoiced,
          status: :settled,
          amount: 50,
          credit_amount: 50)
      end

      it "returns a failure result" do
        expect(result).to be_failure
        expect(result.error.messages[:amount_cents]).to eq(["exceeds_available_amount"])
      end
    end

    context "when outbound amount is zero" do
      let!(:inbound_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :inbound,
          transaction_status: :purchased,
          status: :settled,
          amount: 100,
          credit_amount: 100,
          remaining_amount_cents: 10000)
      end

      let(:outbound_wallet_transaction) do
        create(:wallet_transaction,
          wallet:,
          organization:,
          transaction_type: :outbound,
          transaction_status: :invoiced,
          status: :settled,
          amount: 0,
          credit_amount: 0)
      end

      it "does not create any consumption records" do
        expect { result }.not_to change(WalletTransactionConsumption, :count)
      end

      it "does not decrement inbound remaining_amount_cents" do
        result

        expect(inbound_transaction.reload.remaining_amount_cents).to eq(10000)
      end

      it "returns a success result" do
        expect(result).to be_success
      end
    end
  end
end
