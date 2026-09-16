# frozen_string_literal: true

module Invoices
  module Payments
    class CancelAbandonedService < BaseService
      Result = BaseResult[:payment]

      # Abandoned after a day, and only recovered while recent: cancelling something older means
      # charging and dunning an end customer who has heard nothing for months
      ABANDONED_PERIOD = 24.hours
      RECOVERY_WINDOW = 1.month

      def self.recovery_range
        RECOVERY_WINDOW.ago..ABANDONED_PERIOD.ago
      end

      def initialize(payment:)
        @payment = payment
        super
      end

      def call
        result.payment = payment

        return result unless abandoned?

        intent = stripe_intent
        return result unless intent

        # The intent is already over at the provider and its webhook never reached us
        if ::PaymentProviders::StripeProvider::FAILED_STATUSES.include?(intent.status)
          payment.update!(
            status: intent.status,
            payable_payment_status: payment.payment_provider.determine_payment_status(intent.status)
          )
          unlock_invoice

          return result
        end

        # Only cards do 3DS, and we ask the provider because we do not store the method our side
        return result unless intent.status == "requires_action" && intent.payment_method_type == "card"

        ::PaymentProviders::CancelPaymentService.call!(payment:)

        return result unless payment.reload.failed?

        unlock_invoice

        result
      end

      private

      attr_reader :payment

      delegate :payable, to: :payment

      def stripe_intent
        ::PaymentProviders::Stripe::Payments::RetrieveService.call!(payment:)
      rescue ::Stripe::AuthenticationError, ::Stripe::PermissionError, ::Stripe::InvalidRequestError => e
        Rails.logger.warn(
          "Invoices::Payments::CancelAbandonedService: cannot read intent " \
          "#{payment.provider_payment_id} for payment #{payment.id}: #{e.class.name}"
        )
        nil
      end

      def abandoned?
        return false unless payable.is_a?(Invoice)
        return false unless payment.payment_provider_type == "stripe"
        return false unless payment.awaiting_redirect?
        return false unless self.class.recovery_range.cover?(payment.updated_at)
        return false if payable.payment_succeeded? || payable.voided? || payable.closed?
        # Cancelling would land a failed payment status on the invoice, and that resolves the
        # activation through Invoices::UpdateService. That flow has its own window and its own clock.
        !payment.gated_subscription_activation?
      end

      # The invoice payment status is left alone. A failed payment on a pending invoice is what
      # returns it to dunning, and writing a status here would duplicate the provider's webhook.
      def unlock_invoice
        return if payable.reload.payment_succeeded?

        Invoices::UpdateService.call!(invoice: payable, params: {ready_for_payment_processing: true})
      end
    end
  end
end
