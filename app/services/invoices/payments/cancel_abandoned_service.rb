# frozen_string_literal: true

module Invoices
  module Payments
    # Cancels a provider payment the end customer left sitting in an authentication challenge
    # (Stripe `requires_action` after a 3DS prompt). Until it is cancelled the payment holds the
    # invoice at `ready_for_payment_processing = false` and occupies the unique pending/processing
    # payment slot, so retries, dunning, payment requests and the Pay invoice button are all refused.
    class CancelAbandonedService < BaseService
      Result = BaseResult[:payment]

      def initialize(payment:)
        @payment = payment
        super
      end

      def call
        result.payment = payment

        return result unless cancellable?

        ::PaymentProviders::CancelPaymentService.call!(payment:)

        # The provider refused the cancellation, meaning the intent moved on without us. Its own
        # webhook is the lifecycle authority, so leave the invoice alone.
        return result if payment.reload.processing?

        unlock_invoice

        result
      end

      private

      attr_reader :payment

      delegate :payable, to: :payment

      def cancellable?
        return false unless payable.is_a?(Invoice)
        return false unless payment.status == "requires_action" && payment.processing?

        # `requires_action` also covers payments waiting on an incoming wire, on ACH microdeposits
        # or on an offline voucher. Cancelling those would destroy a collection that is simply in
        # transit, so only an interactive authentication challenge is abandonable.
        return false unless Payment::AUTHENTICATION_NEXT_ACTIONS.include?(payment.provider_payment_data["type"])
        return false if payable.payment_succeeded? || payable.voided? || payable.closed?

        # A gated activation already cancels its own abandoned payment through
        # Subscriptions::ActivationRules::CancelService, on the subscription clock.
        return false if payment.gated_subscription_activation?

        abandoned_at_provider?
      end

      # The stored next action is only a cheap candidate filter: it was written when the intent was
      # created and never refreshed. Before cancelling anything, ask the provider what the intent is
      # doing now, so a challenge that has since been completed, or a payment that was never a
      # challenge at all, is left alone.
      def abandoned_at_provider?
        return false unless payment.payment_provider_type == "stripe"

        ::PaymentProviders::Stripe::Payments::CheckAbandonedAuthenticationService
          .call!(payment:)
          .abandoned
      end

      def unlock_invoice
        # NOTE: only the lock is lifted here. The definitive status is landed by the provider's
        #       `payment_intent.canceled` webhook, which marks the invoice failed and notifies the
        #       customer. Writing `failed` here as well would duplicate that, and would be a status
        #       we invented if the webhook never arrives, so the payment status is left alone.
        Invoices::UpdateService.call!(invoice: payable, params: {ready_for_payment_processing: true})
      end
    end
  end
end
