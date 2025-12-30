# frozen_string_literal: true

require "rails_helper"

RSpec.describe Credits::AppliedPrepaidCreditsService do
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

  describe "#initialize" do
    subject { described_class.new(invoice:, max_wallet_decrease_attempts:) }

    context "when max_wallet_decrease_attempts is less than 1" do
      let(:max_wallet_decrease_attempts) { 0 }

      it "raises an error" do
        expect { subject }.to raise_error(ArgumentError, "max_wallet_decrease_attempts must be between 1 and 6 (inclusive)")
      end
    end

    context "when max_wallet_decrease_attempts is greater than 6" do
      let(:max_wallet_decrease_attempts) { 7 }

      it "raises an error" do
        expect { subject }.to raise_error(ArgumentError, "max_wallet_decrease_attempts must be between 1 and 6 (inclusive)")
      end
    end

    context "when max_wallet_decrease_attempts is between 1 and 6" do
      let(:max_wallet_decrease_attempts) { rand(1..6) }

      it "does not raise an error" do
        expect { subject }.not_to raise_error
      end
    end
  end

  describe "#call" do
    subject(:result) { described_class.call(invoice:) }

    it "calculates prepaid credit" do
      expect(result).to be_success
      expect(result.prepaid_credit_amount_cents).to eq(100)
      expect(invoice.prepaid_credit_amount_cents).to eq(100)
    end

    context "when customer has no applicable wallets" do
      let(:wallets) { [] }

      it "returns early with empty values and no side effects" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(0)
        expect(result.wallet_transactions).to eq([])
        expect(invoice.prepaid_credit_amount_cents).to eq(0)
      end
    end

    it "creates wallet transaction" do
      expect(result).to be_success
      expect(result.wallet_transactions).to be_present
      expect(result.wallet_transactions.count).to eq(1)
      expect(result.wallet_transactions.first.amount).to eq(1.0)
      expect(result.wallet_transactions.first).to be_invoiced
    end

    it "updates wallet balance" do
      subject
      wallet = priority_wallet.reload

      expect(wallet.id).to eq(priority_wallet.id)
      expect(wallet.balance_cents).to eq(900)
      expect(wallet.credits_balance).to eq(9.0)

      [
        normal_wallet,
        limited_charge_wallet,
        priority_limited_charge_wallet,
        limited_subscription_wallet,
        priority_limited_subscription_wallet
      ].each do |w|
        expect(w.reload.balance_cents).to eq(1000)
      end
    end

    it "enqueues a SendWebhookJob" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob)
        .with("wallet_transaction.created", WalletTransaction)
    end

    it "produces an activity log" do
      wallet_transaction = result.wallet_transactions.first

      expect(Utils::ActivityLog).to have_produced("wallet_transaction.created").after_commit.with(wallet_transaction)
    end

    context "when priority wallet credits are less than invoice amount" do
      let(:amount_cents) { 1500 }
      let(:fee_amount_cents) { 1500 }

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(1500)
      end

      it "creates wallet transactions" do
        expect(result).to be_success
        expect(result.wallet_transactions).to be_present
        expect(result.wallet_transactions.count).to eq(2)

        wallet_transaction_1 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_wallet.id }
        wallet_transaction_2 = result.wallet_transactions.detect { |tx| tx.wallet_id == priority_limited_charge_wallet.id }

        expect(wallet_transaction_1.amount).to eq(10.0)
        expect(wallet_transaction_2.amount).to eq(5.0)
      end

      it "updates wallets balance" do
        subject
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
        expect(result).not_to be_success
        expect(result.error.code).to eq("already_applied")
        expect(result.error.error_message).to eq("Prepaid credits already applied")
      end
    end

    context "with fee type limitations" do
      let(:subscription_fees) { [fee, fee2] }
      let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 60, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, precise_amount_cents: 40, taxes_precise_amount_cents: 4) }

      before { subscription_fees }

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(110)
        expect(invoice.prepaid_credit_amount_cents).to eq(110)
      end

      it "creates wallet transaction" do
        expect(result).to be_success
        expect(result.wallet_transactions).to be_present
        expect(result.wallet_transactions.count).to eq(1)
        expect(result.wallet_transactions.first.amount).to eq(1.10)
      end

      it "updates wallet balance" do
        subject
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
          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(5150)
        end

        it "creates wallet transaction" do
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
          subject

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
          limited_charge_wallet
        ]
      end
      let(:subscription_fees) { [fee, fee2] }
      let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 60, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, precise_amount_cents: 40, taxes_precise_amount_cents: 4, charge:) }
      let(:charge) { create(:standard_charge, organization: wallets.first.organization, billable_metric:) }
      let(:billable_metric) { create(:billable_metric, organization: wallets.first.organization) }
      let(:wallet_targets) do
        create(:wallet_target, wallet: limited_bm_wallet, billable_metric:)
        create(:wallet_target, wallet: priority_limited_bm_wallet, billable_metric:)
      end

      before do
        subscription_fees
        wallet_targets
      end

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(110)
        expect(invoice.prepaid_credit_amount_cents).to eq(110)
      end

      it "creates wallet transaction" do
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
        subject
        wallet_priority_limited_subscription = priority_limited_subscription_wallet.reload
        wallet_priority_limited_bm = priority_limited_bm_wallet.reload
        expect(wallet_priority_limited_subscription.balance_cents).to eq(934)
        expect(wallet_priority_limited_subscription.credits_balance).to eq(9.34)
        expect(wallet_priority_limited_bm.balance_cents).to eq(956)
        expect(wallet_priority_limited_bm.credits_balance).to eq(9.56)

        [
          normal_wallet,
          limited_bm_wallet,
          priority_limited_charge_wallet,
          priority_wallet,
          limited_charge_wallet
        ].each do |w|
          expect(w.reload.balance_cents).to eq(1000)
        end
      end

      context "when precise fees have decimals" do
        let(:amount_cents) { 114.4 }
        let(:subscription_fees) { [fee2] }

        let(:fee2) do
          create(
            :charge_fee,
            invoice:,
            subscription:,
            amount_cents: 44,
            precise_amount_cents: 44,
            taxes_precise_amount_cents: 4.4,
            charge:
          )
        end

        it "rounds the decimals" do
          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(114)
        end
      end

      context "when wallet credits are less than invoice amount" do
        let(:subscription_fees) { [fee, fee2] }
        let(:amount_cents) { 10_000 }
        let(:fee) { create(:fee, invoice:, subscription:, amount_cents: 2_000, precise_amount_cents: 2_000, taxes_precise_amount_cents: 200) }
        let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 1_000, precise_amount_cents: 1_000, taxes_precise_amount_cents: 100, charge:) }

        it "calculates prepaid credit" do
          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(3300)
        end

        it "creates wallet transaction" do
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
          subject

          expect(normal_wallet.reload.balance_cents).to eq(800)
          expect(priority_wallet.reload.balance_cents).to eq(0)
          expect(limited_charge_wallet.reload.balance_cents).to eq(1000)
          expect(priority_limited_charge_wallet.reload.balance_cents).to eq(900)
          expect(limited_subscription_wallet.reload.balance_cents).to eq(1000)
          expect(priority_limited_subscription_wallet.reload.balance_cents).to eq(0)
          expect(limited_bm_wallet.reload.balance_cents).to eq(1000)
          expect(priority_limited_bm_wallet.reload.balance_cents).to eq(0)
        end
      end
    end

    context "when wallet is traceable" do
      let(:wallets) { [traceable_wallet] }
      let(:traceable_wallet) do
        create(:wallet, name: "traceable", customer:, balance_cents: 1000, credits_balance: 10.0, traceable: true)
      end
      let!(:inbound_transaction) do
        create(:wallet_transaction,
          wallet: traceable_wallet,
          organization: traceable_wallet.organization,
          transaction_type: :inbound,
          transaction_status: :granted,
          status: :settled,
          amount: 10,
          credit_amount: 10,
          remaining_amount_cents: 1000)
      end

      it "tracks consumption from inbound transactions" do
        expect { result }.to change(WalletTransactionConsumption, :count).by(1)
      end

      it "creates consumption record linking inbound and outbound" do
        result

        consumption = WalletTransactionConsumption.last
        expect(consumption.inbound_wallet_transaction).to eq(inbound_transaction)
        expect(consumption.outbound_wallet_transaction).to eq(result.wallet_transactions.first)
        expect(consumption.consumed_amount_cents).to eq(100)
      end

      it "decrements remaining_amount_cents on inbound transaction" do
        result

        expect(inbound_transaction.reload.remaining_amount_cents).to eq(900)
      end

      it "sets prepaid_granted_credit_amount_cents on invoice" do
        result

        expect(invoice.prepaid_granted_credit_amount_cents).to eq(100)
        expect(invoice.prepaid_purchased_credit_amount_cents).to be_nil
      end

      context "when inbound transaction is purchased" do
        let!(:inbound_transaction) do
          create(:wallet_transaction,
            wallet: traceable_wallet,
            organization: traceable_wallet.organization,
            transaction_type: :inbound,
            transaction_status: :purchased,
            status: :settled,
            amount: 10,
            credit_amount: 10,
            remaining_amount_cents: 1000)
        end

        it "sets prepaid_purchased_credit_amount_cents on invoice" do
          result

          expect(invoice.prepaid_granted_credit_amount_cents).to be_nil
          expect(invoice.prepaid_purchased_credit_amount_cents).to eq(100)
        end
      end

      context "when consuming from both granted and purchased transactions" do
        let(:amount_cents) { 500 }
        let(:fee_amount_cents) { 500 }

        let!(:inbound_transaction) do
          create(:wallet_transaction,
            wallet: traceable_wallet,
            organization: traceable_wallet.organization,
            transaction_type: :inbound,
            transaction_status: :granted,
            status: :settled,
            amount: 3,
            credit_amount: 3,
            remaining_amount_cents: 300)
        end

        let!(:purchased_transaction) do
          create(:wallet_transaction,
            wallet: traceable_wallet,
            organization: traceable_wallet.organization,
            transaction_type: :inbound,
            transaction_status: :purchased,
            status: :settled,
            amount: 7,
            credit_amount: 7,
            remaining_amount_cents: 700)
        end

        it "sets both breakdown amounts on invoice" do
          result

          expect(invoice.prepaid_granted_credit_amount_cents).to eq(300)
          expect(invoice.prepaid_purchased_credit_amount_cents).to eq(200)
        end
      end
    end

    context "when wallet is not traceable" do
      let(:wallets) { [non_traceable_wallet] }
      let(:non_traceable_wallet) do
        create(:wallet, name: "non-traceable", customer:, balance_cents: 1000, credits_balance: 10.0, traceable: false)
      end

      it "does not create consumption records" do
        expect { result }.not_to change(WalletTransactionConsumption, :count)
      end

      it "sets prepaid_purchased_credit_amount_cents on invoice as fallback" do
        result

        expect(invoice.prepaid_granted_credit_amount_cents).to be_nil
        expect(invoice.prepaid_purchased_credit_amount_cents).to eq(100)
      end
    end

    context "when wallet optimistic lock fails" do
      def mock_wallet_balance_decrease_service(succeed_on_attempt: 5)
        attempts = 0
        allow(Wallets::Balance::DecreaseService).to receive(:call).and_wrap_original do |m, *args, **kwargs|
          attempts += 1
          if attempts >= succeed_on_attempt
            next m.call(*args, **kwargs)
          end

          raise ActiveRecord::StaleObjectError
        end
      end

      context "when it succeeds before the max attempts" do
        before do
          mock_wallet_balance_decrease_service(succeed_on_attempt: 6)
        end

        it "retries the operation" do
          expect { subject }.not_to raise_error
        end
      end

      context "when it fails after the max attempts" do
        before do
          mock_wallet_balance_decrease_service(succeed_on_attempt: 7)
        end

        it "raises an error and rolls back the transaction" do
          expect { subject }.to raise_error(ActiveRecord::StaleObjectError)

          transaction_count = customer.wallets.map { |w| w.wallet_transactions.count }.sum
          expect(transaction_count).to eq(0)
        end
      end

      context "when max attempts is specified" do
        subject(:applied_prepaid_credits_service) { described_class.new(invoice:, max_wallet_decrease_attempts: 3) }

        context "when decrease attempts failed" do
          before do
            mock_wallet_balance_decrease_service(succeed_on_attempt: 4)
          end

          it "retries the operation" do
            expect { applied_prepaid_credits_service.call }.to raise_error(ActiveRecord::StaleObjectError)

            transaction_count = customer.wallets.map { |w| w.wallet_transactions.count }.sum
            expect(transaction_count).to eq(0)
          end
        end

        context "when decrease attempts succeed before the max attempts" do
          before do
            mock_wallet_balance_decrease_service(succeed_on_attempt: 3)
          end

          it "raises an error and rolls back the transaction" do
            expect { applied_prepaid_credits_service.call }.not_to raise_error
          end
        end
      end
    end
  end
end
