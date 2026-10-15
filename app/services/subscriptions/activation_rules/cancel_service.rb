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
          if subscription.incomplete?
            cancel_incomplete_subscription
          else
            result.single_validation_failure!(
              field: :subscription,
              error_code: "subscription_already_resolved"
            )
          end
        end

        result.subscription = subscription
        result
      end

      private

      attr_reader :subscription, :rule_status, :cancellation_reason

      def cancel_incomplete_subscription
        invoice = gating_invoice

        if invoice.blank?
          result.single_validation_failure!(
            field: :subscription,
            error_code: "activation_invoice_not_ready"
          )
          return
        end

        payment_rule = subscription.activation_rules.payment.sole
        Payment::EvaluateService.call!(rule: payment_rule, status: rule_status)

        # Locked because Invoices::RetryService reopens a failed invoice under the same lock.
        invoice.with_lock { invoice.closed! }

        ResolveSubscriptionStatusService.call!(subscription:)
        subscription.update!(cancellation_reason:)

        enqueue_psp_cancel(invoice)
        enqueue_recredit_jobs(invoice)
      end

      # A tax provider failure leaves the invoice failed rather than open, and it still has
      # to be closed: Invoices::RetryService would otherwise let a merchant reopen it on a
      # subscription that is no longer activating.
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
