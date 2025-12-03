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
  let(:amount_cents) { 100 }
  let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0) }
  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:) }

  before do
    subscription
  end

  describe "#initialize" do
    context "when max_wallet_decrease_attempts is less than 1" do
      it "raises an error" do
        expect { described_class.new(invoice:, wallets: [wallet], max_wallet_decrease_attempts: 0) }.to raise_error(ArgumentError, "max_wallet_decrease_attempts must be between 1 and 6 (inclusive)")
      end
    end

    context "when max_wallet_decrease_attempts is greater than 6" do
      it "raises an error" do
        expect { described_class.new(invoice:, wallets: [wallet], max_wallet_decrease_attempts: 7) }.to raise_error(ArgumentError, "max_wallet_decrease_attempts must be between 1 and 6 (inclusive)")
      end
    end

    context "when max_wallet_decrease_attempts is between 1 and 6" do
      it "does not raise an error" do
        expect { described_class.new(invoice:, wallets: [wallet], max_wallet_decrease_attempts: 6) }.not_to raise_error
      end
    end
  end

  describe "#call" do
    subject(:result) { described_class.call(invoice:, wallets: [wallet]) }

    it "calculates prepaid credit" do
      expect(result).to be_success
      expect(result.prepaid_credit_amount_cents).to eq(100)
      expect(invoice.prepaid_credit_amount_cents).to eq(100)
    end

    it "creates wallet transaction" do
      expect(result).to be_success
      expect(result.wallet_transaction).to be_present
      expect(result.wallet_transaction.amount).to eq(1.0)
      expect(result.wallet_transaction).to be_invoiced
    end

    it "updates wallet balance" do
      wallet = result.wallet_transaction.wallet

      expect(wallet.balance_cents).to eq(900)
      expect(wallet.credits_balance).to eq(9.0)
    end

    it "enqueues a SendWebhookJob" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob)
        .with("wallet_transaction.created", WalletTransaction)
    end

    it "produces an activity log" do
      wallet_transaction = result.wallet_transaction

      expect(Utils::ActivityLog).to have_produced("wallet_transaction.created").after_commit.with(wallet_transaction)
    end

    context "when wallet credits are less than invoice amount" do
      let(:amount_cents) { 1500 }

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(1000)
      end

      it "creates wallet transaction" do
        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(10.0)
      end

      it "updates wallet balance" do
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance).to eq(0.0)
        expect(wallet.credits_balance).to eq(0.0)
      end
    end

    context "when already applied" do
      let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, transaction_type: "outbound") }

      before { wallet_transaction }

      it "returns error" do
        expect(result).not_to be_success
        expect(result.error.code).to eq("already_applied")
        expect(result.error.error_message).to eq("Prepaid credits already applied")
      end
    end

    context "with fee type limitations" do
      let(:subscription_fees) { [fee1, fee2] }
      let(:fee1) { create(:fee, invoice:, subscription:, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 40, taxes_precise_amount_cents: 4) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0, allowed_fee_types: %w[charge]) }

      before { subscription_fees }

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(44)
        expect(invoice.prepaid_credit_amount_cents).to eq(44)
      end

      it "creates wallet transaction" do
        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(0.44)
        expect(result.wallet_transaction).to be_invoiced
      end

      it "updates wallet balance" do
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance_cents).to eq(956)
        expect(wallet.credits_balance).to eq(9.56)
      end

      context "when wallet credits are less than invoice amount" do
        let(:amount_cents) { 10_000 }
        let(:fee1) { create(:fee, invoice:, subscription:, precise_amount_cents: 6_000, taxes_precise_amount_cents: 600) }
        let(:fee2) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 4_000, taxes_precise_amount_cents: 400) }

        it "calculates prepaid credit" do
          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(1000)
        end

        it "creates wallet transaction" do
          expect(result).to be_success
          expect(result.wallet_transaction).to be_present
          expect(result.wallet_transaction.amount).to eq(10.0)
        end

        it "updates wallet balance" do
          wallet = result.wallet_transaction.wallet

          expect(wallet.balance).to eq(0.0)
          expect(wallet.credits_balance).to eq(0.0)
        end
      end
    end

    context "with billable metric limitations" do
      let(:subscription_fees) { [fee1, fee2] }
      let(:fee1) { create(:fee, invoice:, subscription:, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 40, taxes_precise_amount_cents: 4, charge:) }
      let(:charge) { create(:standard_charge, organization: wallet.organization, billable_metric:) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0) }
      let(:billable_metric) { create(:billable_metric, organization: wallet.organization) }
      let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }

      before do
        subscription_fees
        wallet_target
      end

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(44)
        expect(invoice.prepaid_credit_amount_cents).to eq(44)
      end

      it "creates wallet transaction" do
        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(0.44)
        expect(result.wallet_transaction).to be_invoiced
      end

      it "updates wallet balance" do
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance_cents).to eq(956)
        expect(wallet.credits_balance).to eq(9.56)
      end

      context "when precise fees have decimals" do
        let(:amount_cents) { 110.1 }

        let(:fee2) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 40.1, taxes_precise_amount_cents: 4, charge:) }

        it "rounds the decimals" do
          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(44)
        end
      end

      context "when wallet credits are less than invoice amount" do
        let(:amount_cents) { 10_000 }
        let(:fee1) { create(:fee, invoice:, subscription:, precise_amount_cents: 6_000, taxes_precise_amount_cents: 600) }
        let(:fee2) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 4_000, taxes_precise_amount_cents: 400, charge:) }

        it "calculates prepaid credit" do
          expect(result).to be_success
          expect(result.prepaid_credit_amount_cents).to eq(1000)
        end

        it "creates wallet transaction" do
          expect(result).to be_success
          expect(result.wallet_transaction).to be_present
          expect(result.wallet_transaction.amount).to eq(10.0)
        end

        it "updates wallet balance" do
          wallet = result.wallet_transaction.wallet

          expect(wallet.balance).to eq(0.0)
          expect(wallet.credits_balance).to eq(0.0)
        end
      end
    end

    context "with billable metric limitations and fee type limitation" do
      let(:subscription_fees) { [fee1, fee2, fee3] }
      let(:fee1) { create(:fee, invoice:, subscription:, precise_amount_cents: 60, taxes_precise_amount_cents: 6) }
      let(:fee2) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 20, taxes_precise_amount_cents: 2, charge:) }
      let(:fee3) { create(:charge_fee, invoice:, subscription:, precise_amount_cents: 20, taxes_precise_amount_cents: 2) }
      let(:charge) { create(:standard_charge, organization: wallet.organization, billable_metric:) }
      let(:wallet) { create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0, allowed_fee_types: %w[subscription]) }
      let(:billable_metric) { create(:billable_metric, organization: wallet.organization) }
      let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }

      before do
        subscription_fees
        wallet_target
      end

      it "calculates prepaid credit" do
        expect(result).to be_success
        expect(result.prepaid_credit_amount_cents).to eq(88)
        expect(invoice.prepaid_credit_amount_cents).to eq(88)
      end

      it "creates wallet transaction" do
        expect(result).to be_success
        expect(result.wallet_transaction).to be_present
        expect(result.wallet_transaction.amount).to eq(0.88)
        expect(result.wallet_transaction).to be_invoiced
      end

      it "updates wallet balance" do
        wallet = result.wallet_transaction.wallet

        expect(wallet.balance_cents).to eq(912)
        expect(wallet.credits_balance).to eq(9.12)
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

          expect(wallet.wallet_transactions.count).to eq(0)
        end
      end

      context "when max attempts is specified" do
        subject(:applied_prepaid_credits_service) { described_class.new(invoice:, wallets: [wallet], max_wallet_decrease_attempts: 3) }

        context "when decrease attempts failed" do
          before do
            mock_wallet_balance_decrease_service(succeed_on_attempt: 4)
          end

          it "retries the operation" do
            expect { applied_prepaid_credits_service.call }.to raise_error(ActiveRecord::StaleObjectError)

            expect(wallet.wallet_transactions.count).to eq(0)
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
