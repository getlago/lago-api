# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::VoidService do
  subject(:void_service) { described_class.new(invoice:, params:) }

  let(:params) { {} }

  describe "#call" do
    context "when invoice is nil" do
      let(:invoice) { nil }

      it "returns a failure" do
        result = void_service.call

        aggregate_failures do
          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("invoice")
        end
      end
    end

    context "when invoice is draft" do
      let(:invoice) { create(:invoice, :draft) }

      it "returns a failure" do
        result = void_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end
    end

    context "when the invoice is voided" do
      let(:invoice) { create(:invoice, status: :voided) }

      it "returns a failure" do
        result = void_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end
    end

    context "when the invoice is finalized" do
      let(:invoice) { create(:invoice, :subscription, subscriptions:, status: :finalized, payment_status:, payment_overdue: true) }
      let(:subscriptions) { create_list(:subscription, 1) }

      context "when the payment status is succeeded" do
        let(:payment_status) { :succeeded }

        it "voids the invoice" do
          result = void_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice).to be_voided
            expect(result.invoice.voided_at).to be_present
          end
        end
      end

      context "when the payment status is not succeeded" do
        let(:payment_status) { [:pending, :failed].sample }

        it "voids the invoice" do
          result = void_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(result.invoice).to be_voided
            expect(result.invoice.voided_at).to be_present
            # expect(result.invoice.balance_amount_cents).to eq(0)
          end
        end

        it "enqueues a sync void invoice job" do
          expect do
            void_service.call
          end.to have_enqueued_job(Invoices::ProviderTaxes::VoidJob).with(invoice:)
        end

        it "marks the invoice's payment overdue as false" do
          expect { void_service.call }.to change(invoice, :payment_overdue).from(true).to(false)
        end

        it "flags lifetime usage for refresh" do
          create(:usage_threshold, plan: subscriptions.first.plan)

          void_service.call

          expect(invoice.subscriptions.first.lifetime_usage.recalculate_invoiced_usage).to be(true)
        end

        it "produces an activity log" do
          invoice = described_class.call(invoice:).invoice

          expect(Utils::ActivityLog).to have_produced("invoice.voided").after_commit.with(invoice)
        end

        context "when the invoice has applied credits from the wallet" do
          let(:wallet) { create(:wallet, credits_balance: 100, balance_cents: 100) }
          let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, transaction_type: "outbound", amount: 100, credit_amount: 100) }

          before do
            wallet_transaction
            allow(WalletTransactions::RecreditService).to receive(:call).and_call_original
          end

          it "recredits the wallet transaction" do
            void_service.call
            expect(WalletTransactions::RecreditService).to have_received(:call).with(wallet_transaction: wallet_transaction)
            expect(wallet.wallet_transactions.count).to eq(2)
            expect(wallet.reload.credits_balance).to eq(200)
          end
        end

        context "when the invoice has applied credits from inactive wallet" do
          let(:wallet) { create(:wallet, credits_balance: 100, balance_cents: 100) }
          let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, transaction_type: "outbound", amount: 100, credit_amount: 100) }

          before do
            wallet_transaction
            allow(WalletTransactions::RecreditService).to receive(:call).and_call_original
          end

          it "dont recredit the wallet transaction" do
            wallet.mark_as_terminated!
            void_service.call
            expect(WalletTransactions::RecreditService).not_to have_received(:call)
            expect(wallet.wallet_transactions.count).to eq(1)
            expect(wallet.reload.credits_balance).to eq(100)
          end
        end

        context "when the invoice has credits from applied coupons" do
          let(:coupon) { create(:coupon) }
          let(:applied_coupon) { create(:applied_coupon, coupon: coupon) }
          let!(:credit) { create(:credit, invoice: invoice, applied_coupon: applied_coupon) }

          before do
            allow(AppliedCoupons::RecreditService).to receive(:call!).and_call_original
          end

          it "calls the recredit service for applied coupons" do
            void_service.call
            expect(AppliedCoupons::RecreditService).to have_received(:call!).with(credit: credit)
          end
        end

        context "when the invoice has credits from credit notes" do
          let(:credit_note) { create(:credit_note) }
          let!(:credit) { create(:credit, invoice: invoice, credit_note: credit_note) }

          before do
            allow(CreditNotes::RecreditService).to receive(:call!).and_call_original
          end

          it "dont call the recredit service for credit notes" do
            void_service.call
            expect(CreditNotes::RecreditService).not_to have_received(:call!).with(credit: credit)
          end
        end

        context "when invoice is a purchase credits invoice" do
          let(:invoice) { create(:invoice, :credit, status: :finalized, payment_status:, payment_overdue: true) }
          let(:payment_status) { [:pending, :failed].sample }
          let(:wallet) { create(:wallet, credits_balance: 100, balance_cents: 100) }
          let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, transaction_type: "inbound", amount: 100, credit_amount: 100) }

          before do
            wallet_transaction
            allow(WalletTransactions::RecreditService).to receive(:call).and_call_original
          end

          it "voids the invoice" do
            result = void_service.call

            expect(result).to be_success
            expect(result.invoice).to be_voided
            expect(result.invoice.voided_at).to be_present
          end

          it "does not recredit the wallet transaction" do
            void_service.call

            expect(wallet.wallet_transactions.count).to eq(1)
            expect(wallet.reload.credits_balance).to eq(100)
            expect(WalletTransactions::RecreditService).not_to have_received(:call)
          end
        end
      end
    end

    describe "when generate credit note is true" do
      let(:params) { {generate_credit_note: true} }

      context "when invoice is nil" do
        let(:invoice) { nil }

        it "returns a failure" do
          result = void_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("invoice")
        end
      end

      context "when the invoice is voided" do
        around { |test| lago_premium!(&test) }

        let(:invoice) { create(:invoice, status: :voided) }

        it "returns a failure" do
          result = void_service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end
    end
  end
end
