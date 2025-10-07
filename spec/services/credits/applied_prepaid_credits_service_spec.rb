# frozen_string_literal: true

require "rails_helper"

RSpec.describe Credits::AppliedPrepaidCreditsService do
  subject(:credit_service) { described_class.new(invoice:, wallets: customer.active_wallets_in_application_order) }

  let(:invoice) do
    create(
      :invoice,
      customer:,
      currency: "EUR",
      total_amount_cents: amount_cents
    )
  end
  let(:fee) {
    create(:charge_fee, invoice:, subscription:,
      amount_cents: fee_amount_cents, precise_amount_cents: fee_amount_cents,
      taxes_precise_amount_cents: 0)
  }
  let(:amount_cents) { 100 }
  let(:fee_amount_cents) { 100 }

  let(:normal_wallet) do
    create(:wallet, name: "normal", customer:, balance_cents: 1000, credits_balance: 10.0)
  end

  let(:priority_wallet) do
    create(:wallet, name: "priority", customer:, balance_cents: 1000, credits_balance: 10.0, priority: 49)
  end

  let(:limited_charge_wallet) do
    create(:wallet, name: "limited charge", customer:, balance_cents: 1000, credits_balance: 10.0, allowed_fee_types: %w[charge])
  end

  let(:priority_limited_charge_wallet) do
    create(:wallet, name: "priority limited charge", customer:, balance_cents: 1000, credits_balance: 10.0, priority: 49, allowed_fee_types: %w[charge])
  end

  let(:limited_subscription_wallet) do
    create(:wallet, name: "limited subscription", customer:, balance_cents: 1000, credits_balance: 10.0, allowed_fee_types: %w[subscription])
  end

  let(:priority_limited_subscription_wallet) do
    create(:wallet, name: "priority limited subscription", customer:, balance_cents: 1000, credits_balance: 10.0, priority: 49, allowed_fee_types: %w[subscription])
  end
  let(:wallets) do
    [
      normal_wallet,
      priority_wallet,
      limited_charge_wallet,
      priority_limited_charge_wallet,
      limited_subscription_wallet,
      priority_limited_subscription_wallet
    ]
  end
  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:) }

  before do
    wallets
    fee
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
      expect(result.wallet_transactions).to be_present
      expect(result.wallet_transactions.count).to eq(1)
      expect(result.wallet_transactions.first.amount).to eq(1.0)
      expect(result.wallet_transactions.first).to be_invoiced
    end

    it "updates wallet balance" do
      credit_service.call
      wallet = priority_wallet.reload

      expect(wallet.id).to eq(priority_wallet.id)
      expect(wallet.balance_cents).to eq(900)
      expect(wallet.credits_balance).to eq(9.0)

      [normal_wallet,
       limited_charge_wallet,
       priority_limited_charge_wallet,
       limited_subscription_wallet,
       priority_limited_subscription_wallet].each do |w|
        expect(w.reload.balance_cents).to eq(1000)
      end
    end

    it "enqueues a SendWebhookJob" do
      expect { credit_service.call }.to have_enqueued_job(SendWebhookJob)
        .with("wallet_transaction.created", WalletTransaction)
    end

    it "produces an activity log" do
      wallet_transaction = described_class.call(invoice:, wallets:).wallet_transactions.first

      expect(Utils::ActivityLog).to have_produced("wallet_transaction.created").after_commit.with(wallet_transaction)
    end

    context "when priority wallet credits are less than invoice amount" do
      let(:amount_cents) { 1500 }
      let(:fee_amount_cents) { 1500 }

      it "calculates prepaid credit" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(1500)
      end

      it "creates wallet transactions" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transactions).to be_present
        expect(result.wallet_transactions.count).to eq(2)

        wallet_transaction_1 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_wallet.id }
        wallet_transaction_2 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_charge_wallet.id }

        expect(wallet_transaction_1.amount).to eq(10.0)
        expect(wallet_transaction_2.amount).to eq(5.0)
      end

      it "updates wallets balance" do
        result = credit_service.call
        wallet_priority = priority_wallet.reload
        wallet_priority_limited_charge = priority_limited_charge_wallet.reload

        expect(wallet_priority.balance).to eq(0.0)
        expect(wallet_priority.credits_balance).to eq(0.0)
        expect(wallet_priority_limited_charge.balance_cents).to eq(500)
        expect(wallet_priority_limited_charge.credits_balance).to eq(5.0)
        [normal_wallet,
         limited_charge_wallet,
         limited_subscription_wallet,
         priority_limited_subscription_wallet].each do |w|
          expect(w.reload.balance_cents).to eq(1000)
        end
      end
    end

    context "when already applied" do
      let(:wallet_transaction) { create(:wallet_transaction, wallet: wallets.first, invoice:, transaction_type: "outbound") }

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
      let(:subscription_fees) { [fee, fee2] }
      let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 60, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, precise_amount_cents: 40, taxes_precise_amount_cents: 4) }

      before { subscription_fees }

      it "calculates prepaid credit" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(110)
        expect(invoice.prepaid_credit_amount_cents).to eq(110)
      end

      it "creates wallet transaction" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transactions).to be_present
        expect(result.wallet_transactions.count).to eq(1)
        expect(result.wallet_transactions.first.amount).to eq(1.10)
      end

      it "updates wallet balance" do
        credit_service.call
        wallet = priority_wallet.reload

        expect(wallet.balance_cents).to eq(890)
        expect(wallet.credits_balance).to eq(8.90)
        [normal_wallet,
         limited_charge_wallet,
         priority_limited_charge_wallet,
         limited_subscription_wallet,
         priority_limited_subscription_wallet].each do |w|
          expect(w.reload.balance_cents).to eq(1000)
        end
      end

      context "when wallet credits are less than invoice amount" do
        let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 3500, precise_amount_cents: 3500, taxes_precise_amount_cents: 100) }
        let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 1500, precise_amount_cents: 1500, taxes_precise_amount_cents: 50) }

        it "calculates prepaid credit" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(5150)
        end

        it "creates wallet transaction" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.wallet_transactions).to be_present
          expect(result.wallet_transactions.count).to eq(6)
          wallet_transaction_1 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_wallet.id }
          wallet_transaction_2 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_charge_wallet.id }
          wallet_transaction_3 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_subscription_wallet.id }
          wallet_transaction_4 = result.wallet_transactions.detect { |tx| tx.wallet_id == normal_wallet.id }
          wallet_transaction_5 = result.wallet_transactions.detect { |tx| tx.wallet_id == limited_charge_wallet.id }
          wallet_transaction_6 = result.wallet_transactions.detect { |tx| tx.wallet_id == limited_subscription_wallet.id }

          expect(wallet_transaction_1.amount).to eq(10.0)
          expect(wallet_transaction_2.amount).to eq(10.0)
          expect(wallet_transaction_3.amount).to eq(10.0)
          expect(wallet_transaction_4.amount).to eq(10.0)
          expect(wallet_transaction_5.amount).to eq(5.5)
          expect(wallet_transaction_6.amount).to eq(6.0)
        end

        it "updates wallet balance" do
          credit_service.call

          expect(normal_wallet.reload.balance_cents).to eq(0)
          expect(priority_wallet.reload.balance_cents).to eq(0)
          expect(limited_charge_wallet.reload.balance_cents).to eq(450)
          expect(priority_limited_charge_wallet.reload.balance_cents).to eq(0)
          expect(limited_subscription_wallet.reload.balance_cents).to eq(400)
          expect(priority_limited_subscription_wallet.reload.balance_cents).to eq(0)
        end
      end
    end

    context "with billable metric limitations" do
      let(:limited_bm_wallet) do
        create(:wallet, name: "limited bm wallet", customer:, balance_cents: 1000, credits_balance: 10.0)
      end
      let(:priority_limited_bm_wallet) do
        create(:wallet, name: "priority limited bm wallet", customer:, balance_cents: 1000, credits_balance: 10.0, priority: 49)
      end
      let(:wallets) do
        [
          normal_wallet,
          limited_subscription_wallet,
          priority_limited_subscription_wallet,
          limited_bm_wallet,
          priority_limited_bm_wallet,
          priority_limited_charge_wallet,
          priority_wallet,
          limited_charge_wallet,
        ]
      end
      let(:subscription_fees) { [fee, fee2] }
      let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 60, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, precise_amount_cents: 40, taxes_precise_amount_cents: 4, charge:) }
      let(:charge) { create(:standard_charge, organization: wallets.first.organization, billable_metric:) }
      let(:billable_metric) { create(:billable_metric, organization: wallets.first.organization) }
      let(:wallet_target) { create(:wallet_target, wallet: limited_bm_wallet, billable_metric:) }
      let(:wallet_target) { create(:wallet_target, wallet: priority_limited_bm_wallet, billable_metric:) }

      before do
        subscription_fees
        wallet_target
      end

      it "calculates prepaid credit" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(110)
        expect(invoice.prepaid_credit_amount_cents).to eq(110)
      end

      it "creates wallet transaction" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transactions).to be_present
        expect(result.wallet_transactions.count).to eq(2)

        wallet_transaction_1 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_subscription_wallet.id }
        wallet_transaction_2 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_bm_wallet.id }

        expect(wallet_transaction_1.amount).to eq(0.66)
        expect(wallet_transaction_2.amount).to eq(0.44)
        expect(wallet_transaction_1).to be_invoiced
        expect(wallet_transaction_2).to be_invoiced
      end

      it "updates wallet balance" do
        credit_service.call
        wallet_priority_limited_subscription = priority_limited_subscription_wallet.reload
        wallet_priority_limited_bm = priority_limited_bm_wallet.reload
        expect(wallet_priority_limited_subscription.balance_cents).to eq(934)
        expect(wallet_priority_limited_subscription.credits_balance).to eq(9.34)
        expect(wallet_priority_limited_bm.balance_cents).to eq(956)
        expect(wallet_priority_limited_bm.credits_balance).to eq(9.56)
        [normal_wallet,
         limited_bm_wallet,
         priority_limited_charge_wallet,
         priority_wallet,
         limited_charge_wallet
        ].each do |w|
          expect(w.reload.balance_cents).to eq(1000)
        end
      end

      context "when wallet credits are less than invoice amount" do
        let(:subscription_fees) { [fee, fee2] }
        let(:amount_cents) { 10_000 }
        let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 2_000, precise_amount_cents: 2_000, taxes_precise_amount_cents: 200) }
        let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 1_000, precise_amount_cents: 1_000, taxes_precise_amount_cents: 100, charge:) }

        it "calculates prepaid credit" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(3300)
        end

        it "creates wallet transaction" do
          result = credit_service.call

          expect(result).to be_success
          expect(result.wallet_transactions).to be_present
          expect(result.wallet_transactions.count).to eq(5)

          wallet_transaction_1 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_subscription_wallet.id }
          wallet_transaction_2 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_bm_wallet.id }
          wallet_transaction_3 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_charge_wallet.id }
          wallet_transaction_4 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_wallet.id }
          wallet_transaction_5 = result.wallet_transactions.detect { |tx| tx.wallet_id == normal_wallet.id }

          expect(wallet_transaction_1.amount).to eq(10)
          expect(wallet_transaction_2.amount).to eq(10)
          expect(wallet_transaction_3.amount).to eq(1)
          expect(wallet_transaction_4.amount).to eq(10)
          expect(wallet_transaction_5.amount).to eq(2)
        end

        it "updates wallet balance" do
          result = credit_service.call
          wallet = result.wallet_transactions.first.wallet

          expect(wallet.balance).to eq(0.0)
          expect(wallet.credits_balance).to eq(0.0)
        end
      end
    end

    context "with billable metric limitations and fee type limitation" do
      let(:subscription_fees) { [fee, fee2, fee3] }
      let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 60, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, precise_amount_cents: 20, taxes_precise_amount_cents: 2, charge:) }
      let(:fee3) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, precise_amount_cents: 20, taxes_precise_amount_cents: 2) }
      let(:charge) { create(:standard_charge, organization: wallets.first.organization, billable_metric:) }
      let(:wallets) { [create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0, allowed_fee_types: %w[subscription])] }
      let(:billable_metric) { create(:billable_metric, organization: wallets.first.organization) }
      let(:wallet_target) { create(:wallet_target, wallet: wallets.first, billable_metric:) }

      before do
        subscription_fees
        wallet_target
      end

      it "calculates prepaid credit" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(88)
        expect(invoice.prepaid_credit_amount_cents).to eq(88)
      end

      it "creates wallet transaction" do
        result = credit_service.call

        expect(result).to be_success
        expect(result.wallet_transactions).to be_present
        expect(result.wallet_transactions.first.amount).to eq(0.88)
        expect(result.wallet_transactions.first).to be_invoiced
      end

      it "updates wallet balance" do
        result = credit_service.call
        wallet = result.wallet_transactions.first.wallet

        expect(wallet.balance_cents).to eq(912)
        expect(wallet.credits_balance).to eq(9.12)
      end
    end
  end
end
