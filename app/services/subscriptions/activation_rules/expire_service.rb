# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class ExpireService < BaseService
      Result = BaseResult[:subscription]

      def initialize(subscription:)
        @subscription = subscription
        super
      end

      def call
        subscription.with_lock do
          # Race protection: a payment webhook may resolve the subscription
          # concurrently. If it already did so by the time we acquired the
          # lock, bail.
          next unless subscription.incomplete?

          payment_rule = subscription.activation_rules.payment.sole
          Payment::EvaluateService.call!(rule: payment_rule, status: :expired)

          invoice = subscription.invoices.open.subscription.sole
          invoice.closed!

          ResolveSubscriptionStatusService.call!(subscription:)
          subscription.update!(cancelation_reason: :timeout) if subscription.canceled?

          enqueue_psp_cancel(invoice)
        end

        result.subscription = subscription
        result
      end

      private

      attr_reader :subscription

      def enqueue_psp_cancel(invoice)
        payment = invoice.payments
          .where(payable_payment_status: %w[pending processing])
          .order(created_at: :desc)
          .first
        return unless payment

        PaymentProviders::CancelPaymentJob.perform_after_commit(payment)
      end
    end
  end
end
