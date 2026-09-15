# frozen_string_literal: true

module Invoices
  module Payments
    class CancelAbandonedService < BaseService
      Result = BaseResult[:payment]

      # A redirect is abandoned once the customer has had a day to come back, and is only recovered
      # automatically while it is recent. Anything that went stale before the window opened belongs
      # to a backlog that predates this job, and cancelling it means charging and dunning an end
      # customer who has heard nothing for months — that needs a decision, not a clock.
      ABANDONED_PERIOD = 24.hours
      RECOVERY_WINDOW = 1.month

      def initialize(payment:)
        @payment = payment
        super
      end

      def call
        result.payment = payment

        return result unless cancellable?

        ::PaymentProviders::CancelPaymentService.call!(payment:)

        return result if payment.reload.processing?

        unlock_invoice

        result
      end

      private

      attr_reader :payment

      delegate :payable, to: :payment

      def cancellable?
        return false unless payable.is_a?(Invoice)
        return false unless abandoned_at_redirect?
        return false if payable.payment_succeeded? || payable.voided? || payable.closed?

        # Cancelling here would land a failed payment status on the invoice, and that resolves the
        # subscription activation through Invoices::UpdateService. A gated activation has its own
        # window and its own clock, so it is left to decide when its payment has run out of time.
        return false if payment.gated_subscription_activation?

        confirmed_by_provider?
      end

      # The local columns cannot tell a card apart from a redirect-based alternative method: the
      # payment method is unknown on most rows, and `provider_payment_method_data` is only ever
      # written by the `payment_intent.succeeded` webhook, so a payment stuck before success has it
      # empty by construction. Only cards do 3DS, so the provider is asked before anything is
      # cancelled. The answer also catches an intent that moved on without us.
      def confirmed_by_provider?
        return false unless payment.payment_provider_type == "stripe"

        live = ::PaymentProviders::Stripe::Payments::RetrieveService.call!(payment:)
        live.status == "requires_action" && live.payment_method_type == "card"
      rescue ::Stripe::AuthenticationError, ::Stripe::PermissionError, ::Stripe::InvalidRequestError => e
        Rails.logger.warn(
          "Invoices::Payments::CancelAbandonedService: cannot read intent " \
          "#{payment.provider_payment_id} for payment #{payment.id}: #{e.class.name}"
        )
        false
      end

      def abandoned_at_redirect?
        payment.status == "requires_action" &&
          payment.processing? &&
          payment.provider_payment_data&.dig("type") == "redirect_to_url" &&
          payment.updated_at.between?(RECOVERY_WINDOW.ago, ABANDONED_PERIOD.ago)
      end

      def unlock_invoice
        Invoices::UpdateService.call!(invoice: payable, params: {ready_for_payment_processing: true})
      end
    end
  end
end
