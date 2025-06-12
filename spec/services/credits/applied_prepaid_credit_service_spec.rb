# frozen_string_literal: true

require "rails_helper"

RSpec.describe Credits::AppliedPrepaidCreditService do
  subject(:credit_service) { described_class.new(invoice:, wallet:) }

  let(:invoice) do
    create(
      :invoice,
      customer:,
      currency: "EUR",
      total_amount_cents: amount_cents
    )
  end
  let(:amount_cents) { 100 }
  let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0) }
  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:) }

  before do
    allow(Utils::ActivityLog).to receive(:produce)

    subscription
  end

  describe "#call" do
    it "calculates prepaid credit" do
      result = credit_service.call

      expect(result).to be_success
      expect(result.prepaid_credit_amount_cents).to eq(100)
      expect(invoice.prepaid_credit_amount_cents).to eq(100)
    end

    it "creates wallet transaction" do
      result = credit_service.call

      expect(result).to be_success
      expect(result.wallet_transaction).to be_present
      expect(result.wallet_transaction.amount).to eq(1.0)
      expect(result.wallet_transaction).to be_invoiced
    end

    it "updates wallet balance" do
      result = credit_service.call
      wallet = result.wallet_transaction.wallet

      expect(wallet.balance_cents).to eq(900)
      expect(wallet.credits_balance).to eq(9.0)
    end

    it "enqueues a SendWebhookJob" do
      expect { credit_service.call }.to have_enqueued_job(SendWebhookJob)
        .with("wallet_transaction.created", WalletTransaction)
    end

    it "produces an activity log" do
      wallet_transaction = described_class.call(invoice:, wallet:).wallet_transaction

      expect(Utils::ActivityLog).to have_received(:produce).with(wallet_transaction, "wallet_transaction.created")
    end

    context "when wallet credits are less than invoice amount" do
      let(:amount_cents) { 1500 }

      it "calculates prepaid credit" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(1000)
      end

      it "creates wallet transaction" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(10.0)
      end

      it "updates wallet balance" do
        result = credit_service.call
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance).to eq(0.0)
        expect(wallet.credits_balance).to eq(0.0)
      end
    end

    context "when already applied" do
      let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, transaction_type: "outbound") }

      before { wallet_transaction }

      it "returns error" do
        result = credit_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.code).to eq("already_applied")
          expect(result.error.error_message).to eq("Prepaid credits already applied")
        end
      end
    end

    context "with fee type limitations" do
      let(:subscription_fees) { [fee1, fee2] }
      let(:fee1) { create(:fee, invoice:, subscription:, amount_cents: 60, taxes_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, taxes_amount_cents: 4) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0, allowed_fee_types: %w[charge]) }

      before { subscription_fees }

      it "calculates prepaid credit" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(44)
        expect(invoice.prepaid_credit_amount_cents).to eq(44)
      end

      it "creates wallet transaction" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(0.44)
        expect(result.wallet_transaction).to be_invoiced
      end

      it "updates wallet balance" do
        result = credit_service.call
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance_cents).to eq(956)
        expect(wallet.credits_balance).to eq(9.56)
      end

      context "when wallet credits are less than invoice amount" do
        let(:amount_cents) { 10_000 }
        let(:fee1) { create(:fee, invoice:, subscription:, amount_cents: 6_000, taxes_amount_cents: 600) }
        let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 4_000, taxes_amount_cents: 400) }

        it "calculates prepaid credit" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(1000)
        end

        it "creates wallet transaction" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.wallet_transaction).to be_present
          expect(result.wallet_transaction.amount).to eq(10.0)
        end

        it "updates wallet balance" do
          result = credit_service.call
          wallet = result.wallet_transaction.wallet

          expect(wallet.balance).to eq(0.0)
          expect(wallet.credits_balance).to eq(0.0)
        end
      end
    end
  end
end
