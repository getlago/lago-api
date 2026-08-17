# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class CancelService < BaseService
      Result = BaseResult[:subscription]

      def initialize(subscription:, rule_status:, cancellation_reason:)
        @subscription = subscription
        @rule_status = rule_status
        @cancellation_reason = cancellation_reason
        super
      end

      def call
        subscription.with_lock do
          # A payment webhook may resolve the subscription while we wait for the lock.
          next unless subscription.incomplete?

          payment_rule = subscription.activation_rules.payment.sole
          Payment::EvaluateService.call!(rule: payment_rule, status: rule_status)

          invoice = gating_invoice
          invoice&.closed!

          ResolveSubscriptionStatusService.call!(subscription:)
          subscription.update!(cancellation_reason:)

          if invoice
            enqueue_psp_cancel(invoice)
            enqueue_recredit_jobs(invoice)
          end
        end

        result.subscription = subscription
        result
      end

      private

      attr_reader :subscription, :rule_status, :cancellation_reason

      # A tax provider failure leaves the invoice failed rather than open, and it still has
      # to be closed: Invoices::RetryService would otherwise let a merchant reopen it on a
      # subscription that is no longer activating. It is absent altogether in the window
      # between gating the subscription and BillSubscriptionJob creating it.
      def gating_invoice
        subscription.invoices.subscription.where(status: %i[open failed]).first
      end

      def enqueue_recredit_jobs(invoice)
        invoice.credits.coupon_kind.find_each do |credit|
          AppliedCoupons::RecreditJob.perform_after_commit(credit)
        end

        invoice.credits.credit_note_kind.find_each do |credit|
          CreditNotes::RecreditJob.perform_after_commit(credit)
        end

        invoice.wallet_transactions.outbound.find_each do |wallet_transaction|
          WalletTransactions::RecreditJob.perform_after_commit(wallet_transaction)
        end
      end

      def enqueue_psp_cancel(invoice)
        # A partial unique index allows at most one payment in (pending, processing) per invoice.
        payment = invoice.payments
          .where(payable_payment_status: %w[pending processing])
          .first
        return unless payment

        PaymentProviders::CancelPaymentJob.perform_after_commit(payment)
      end
    end
  end
end
