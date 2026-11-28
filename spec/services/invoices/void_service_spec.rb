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

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("invoice")
      end
    end

    context "when invoice is draft" do
      let(:invoice) { create(:invoice, :draft) }

      it "returns a failure" do
        result = void_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("not_voidable")
      end
    end

    context "when the invoice is voided" do
      let(:invoice) { create(:invoice, status: :voided) }

      it "returns a failure" do
        result = void_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("not_voidable")
      end
    end

    context "when the invoice is finalized" do
      let(:invoice) { create(:invoice, :subscription, subscriptions:, status: :finalized, payment_status:, payment_overdue: true) }
      let(:subscriptions) { create_list(:subscription, 1) }

      context "when the payment status is succeeded" do
        let(:payment_status) { :succeeded }

        it "voids the invoice" do
          result = void_service.call

          expect(result).to be_success
          expect(result.invoice).to be_voided
          expect(result.invoice.voided_at).to be_present
        end
      end

      context "when the payment status is not succeeded" do
        let(:payment_status) { [:pending, :failed].sample }

        it "voids the invoice" do
          result = void_service.call

          expect(result).to be_success
          expect(result.invoice).to be_voided
          expect(result.invoice.voided_at).to be_present
          # expect(result.invoice.balance_amount_cents).to eq(0)
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

        context "with a provider payment awaiting funds" do
          let(:payment) { create(:payment, :awaiting_bank_transfer, payable: invoice, payable_payment_status: :processing) }

          before { payment }

          it "enqueues a job to cancel the provider payment" do
            expect { void_service.call }.to have_enqueued_job_after_commit(PaymentProviders::CancelPaymentJob).with(payment)
          end
        end

        context "without an open provider payment" do
          before { create(:payment, payable: invoice, status: "failed", payable_payment_status: :failed) }

          it "does not enqueue a cancel job" do
            expect { void_service.call }.not_to have_enqueued_job(PaymentProviders::CancelPaymentJob)
          end
        end

        context "when the invoice has applied credits from the wallet" do
          let(:wallet) { create(:wallet, credits_balance: 100, balance_cents: 100) }
          let(:wallet_transaction) do
            create(:wallet_transaction,
              wallet:,
              invoice:,
              purchase_order_number: "PO-123",
              transaction_type: "outbound",
              amount: 100,
              credit_amount: 100)
          end

          before do
            wallet_transaction
            allow(WalletTransactions::RecreditService).to receive(:call).and_call_original
          end

          it "recredits the wallet transaction" do
            void_service.call
            expect(WalletTransactions::RecreditService).to have_received(:call).with(wallet_transaction: wallet_transaction)
            expect(wallet.wallet_transactions.count).to eq(2)
            expect(wallet.reload.credits_balance).to eq(200)
            expect(wallet.wallet_transactions.inbound.last.purchase_order_number).to eq(wallet_transaction.purchase_order_number)
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

          it "does not fail a settled top-up" do
            create(:credit_fee, invoice:, wallet_transaction:)

            void_service.call

            expect(wallet_transaction.reload).to be_settled
          end

          context "when its top-up is still pending" do
            # Found through the credit fee, as Invoices::PrepaidCreditJob does
            let(:pending_top_up) do
              create(:wallet_transaction, wallet:, status: :pending, settled_at: nil, transaction_status: :purchased, amount: 50, credit_amount: 50)
            end
            let(:other_pending_top_up) do
              create(:wallet_transaction, wallet:, status: :pending, settled_at: nil, transaction_status: :purchased, amount: 20, credit_amount: 20)
            end

            before do
              create(:credit_fee, invoice:, wallet_transaction: pending_top_up)
              other_pending_top_up
            end

            it "fails the pending top-up and sends its webhook" do
              void_service.call

              expect(pending_top_up.reload).to be_failed
              expect(pending_top_up.failed_at).to be_present
              expect(SendWebhookJob).to have_been_enqueued.with("wallet_transaction.updated", pending_top_up)
            end

            it "leaves the pending top-ups of other invoices alone" do
              void_service.call

              expect(other_pending_top_up.reload).to be_pending
            end

            context "when a payment link was opened before the void" do
              let(:payment_intent) { create(:payment_intent, invoice:, status: :active) }

              before { payment_intent }

              it "expires the payment link, so it cannot settle the failed top-up" do
                void_service.call

                expect(payment_intent.reload).to be_expired
                expect(pending_top_up.reload).to be_failed
              end

              context "when the provider refuses to expire it" do
                before do
                  allow(PaymentIntents::ExpireService).to receive(:call!)
                    .and_raise(BaseService::ServiceFailure.new(BaseResult.new, code: "stripe_error", error_message: "boom"))
                end

                it "does not void the invoice, so the link cannot pay a failed top-up" do
                  result = void_service.call

                  expect(result).not_to be_success
                  expect(invoice.reload).to be_finalized
                  expect(pending_top_up.reload).to be_pending
                end
              end

              context "when Stripe cannot be reached" do
                before do
                  allow(PaymentIntents::ExpireService).to receive(:call!).and_raise(::Stripe::APIConnectionError.new("timeout"))
                end

                it "fails cleanly without voiding, so it can be retried" do
                  result = void_service.call

                  expect(result).not_to be_success
                  expect(result.error.code).to eq("payment_link_expiration_failed")
                  expect(invoice.reload).to be_finalized
                  expect(pending_top_up.reload).to be_pending
                end
              end

              context "when the customer's payment provider was removed" do
                let(:payment_intent) { create(:payment_intent, invoice:, status: :active, provider_session_id: "cs_test_123") }

                before { invoice.customer.update!(payment_provider: nil) }

                it "expires the link on Lago's side and voids the invoice" do
                  result = void_service.call

                  expect(result).to be_success
                  expect(invoice.reload).to be_voided
                  expect(payment_intent.reload).to be_expired
                  expect(pending_top_up.reload).to be_failed
                end
              end

              context "when the customer moved to a provider that cannot expire links" do
                before do
                  allow(PaymentIntents::ExpireService).to receive(:call!)
                    .and_raise(ArgumentError, "Invoices::Payments::GocardlessService: :expire_payment_url is not declared in RESULTS")
                end

                it "expires the link on Lago's side and voids the invoice" do
                  result = void_service.call

                  expect(result).to be_success
                  expect(payment_intent.reload).to be_expired
                  expect(pending_top_up.reload).to be_failed
                end
              end

              context "when an unrelated ArgumentError is raised" do
                before { allow(PaymentIntents::ExpireService).to receive(:call!).and_raise(ArgumentError, "bug") }

                it "does not hide it" do
                  expect { void_service.call }.to raise_error(ArgumentError, "bug")
                end
              end
            end

            context "when its payment is still processing, as a SEPA debit" do
              before do
                create(:payment, payable: invoice, customer: invoice.customer, organization: invoice.organization,
                  status: "processing", payable_payment_status: :processing)
              end

              it "leaves the top-up pending for the provider's webhook to settle or fail" do
                void_service.call

                expect(pending_top_up.reload).to be_pending
                expect(SendWebhookJob).not_to have_been_enqueued.with("wallet_transaction.updated", pending_top_up)
              end
            end
          end
        end

        context "when a subscription invoice has a pending top-up fee" do
          let(:payment_status) { :pending }
          let(:pending_top_up) do
            create(:wallet_transaction, status: :pending, settled_at: nil, transaction_status: :purchased)
          end

          before { create(:credit_fee, invoice:, wallet_transaction: pending_top_up) }

          it "leaves the top-up alone" do
            void_service.call

            expect(pending_top_up.reload).to be_pending
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

      context "when the invoice is voided", :premium do
        let(:invoice) { create(:invoice, status: :voided) }

        it "returns a failure" do
          result = void_service.call
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end

      context "when the invoice has progressive billing credits", :premium do
        let(:params) { {generate_credit_note: true, credit_amount: 200} }
        let(:organization) { create(:organization) }
        let(:customer) { create(:customer, organization:) }
        let(:plan) { create(:plan, organization:) }
        let(:subscription) { create(:subscription, customer:, organization:, plan:) }
        let(:invoice) do
          create(
            :invoice,
            customer:,
            organization:,
            invoice_type: :subscription,
            status: :finalized,
            payment_status: :pending,
            fees_amount_cents: 400,
            progressive_billing_credit_amount_cents: 200,
            sub_total_excluding_taxes_amount_cents: 200,
            sub_total_including_taxes_amount_cents: 200,
            total_amount_cents: 200
          )
        end
        let(:charge) { create(:standard_charge, plan:) }
        let(:invoice_subscription) do
          create(:invoice_subscription, invoice:, subscription:, organization:)
        end
        let(:fee) do
          create(
            :charge_fee,
            invoice:,
            subscription:,
            charge:,
            amount_cents: 400,
            precise_amount_cents: 400,
            precise_coupons_amount_cents: 0,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0
          )
        end

        before do
          invoice_subscription
          fee
        end

        it "creates the requested credit note from the net remaining amount" do
          result = void_service.call

          expect(result).to be_success
          expect(result.invoice).to be_voided

          credit_note = invoice.credit_notes.find_by!(credit_status: :available)
          expect(credit_note.total_amount_cents).to eq(200)
          expect(credit_note.credit_amount_cents).to eq(200)
          expect(credit_note.items.sole.amount_cents).to eq(200)
        end
      end

      context "when a credit note service fails", :premium do
        let(:invoice) do
          create(
            :invoice,
            status: :finalized,
            payment_status: :pending,
            fees_amount_cents: 100,
            sub_total_excluding_taxes_amount_cents: 100,
            sub_total_including_taxes_amount_cents: 100,
            total_amount_cents: 100
          )
        end

        before do
          create(
            :fee,
            invoice:,
            amount_cents: 100,
            precise_amount_cents: 100,
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0
          )
        end

        context "when the estimate fails" do
          before do
            allow(CreditNotes::EstimateService).to receive(:call)
              .and_return(CreditNotes::EstimateService::Result.new.not_allowed_failure!(code: "invalid_type_or_status"))
          end

          it "returns the failure and keeps the invoice finalized" do
            result = void_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("invalid_type_or_status")
            expect(invoice.reload).to be_finalized
            expect(invoice.credit_notes).to be_empty
          end
        end

        context "when the credit note creation fails" do
          before do
            allow(CreditNotes::CreateService).to receive(:call)
              .and_return(CreditNotes::CreateService::Result.new.not_allowed_failure!(code: "invalid_type_or_status"))
          end

          it "returns the failure and keeps the invoice finalized" do
            result = void_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("invalid_type_or_status")
            expect(invoice.reload).to be_finalized
            expect(invoice.credit_notes).to be_empty
          end
        end

        context "when the credit note void fails" do
          before do
            allow(CreditNotes::VoidService).to receive(:call)
              .and_return(CreditNotes::VoidService::Result.new.not_allowed_failure!(code: "no_voidable_amount"))
          end

          it "returns the failure and rolls back the credit note" do
            result = void_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
            expect(result.error.code).to eq("no_voidable_amount")
            expect(CreditNotes::VoidService).to have_received(:call).with(credit_note: an_instance_of(CreditNote))
            expect(invoice.reload).to be_finalized
            expect(invoice.credit_notes).to be_empty
          end
        end
      end
    end

    describe "guard against concurrent calls" do
      let(:invoice) { create(:invoice, status: :finalized) }

      context "with two threads racing on the same invoice", transaction: false do
        # Separate in-memory instances of the same database record
        let!(:invoice_instances) do
          Array.new(2) do
            inv = Invoice.find(invoice.id)

            allow(inv).to receive(:void!).and_wrap_original do |original, *args|
              sleep(0.05)
              original.call(*args)
            end

            inv
          end
        end

        it "voids the invoice exactly once and rejects other attempts" do
          allow(LifetimeUsages::FlagRefreshFromInvoiceService).to receive(:call).and_call_original

          results = Concurrent::Array.new

          threads = invoice_instances.map do |inv|
            Thread.new do
              results << described_class.call(invoice: inv)
            end
          end

          threads.each(&:join)

          successes = results.count(&:success?)
          rejections = results.count { |r| !r.success? && r.error.code == "not_voidable" }

          expect(successes).to eq(1)
          expect(rejections).to eq(1)
          expect(invoice.reload).to be_voided
          expect(LifetimeUsages::FlagRefreshFromInvoiceService).to have_received(:call).once
        end
      end
    end
  end
end
