# frozen_string_literal: true

module Invoices
  module Payments
    class CancelAbandonedService < BaseService
      Result = BaseResult[:payment]

      ABANDONED_PERIOD = 24.hours
      RECOVERY_WINDOW = 1.month

      def initialize(payment:)
        @payment = payment
        super
      end

      def call
        result.payment = payment

        return result unless abandoned?

        intent = stripe_intent
        return result unless intent

        # The intent is already over at the provider and its webhook never arrived, which is what
        # the merchant creates by cancelling in the dashboard by hand. Nothing left to cancel: the
        # row is brought in line with what the provider reports, as the webhook would have done.
        # Its own word goes in `status` and ours in `payable_payment_status`, the same way
        # PaymentProviders::Stripe::Payments::CancelService writes them on the path below.
        if ::PaymentProviders::StripeProvider::FAILED_STATUSES.include?(intent.status)
          payment.update!(
            status: intent.status,
            payable_payment_status: payment.payment_provider.determine_payment_status(intent.status)
          )
          unlock_invoice

          return result
        end

        # Local columns cannot tell a card from a redirect-based alternative method: the payment
        # method is unknown on most rows, and `provider_payment_method_data` is only ever written
        # by the succeeded webhook, so a payment stuck before success has it empty by construction.
        # Only cards do 3DS, so the provider decides.
        return result unless intent.status == "requires_action" && intent.payment_method_type == "card"

        ::PaymentProviders::CancelPaymentService.call!(payment:)

        # Only a payment that actually reached a failed state was cancelled. "No longer processing"
        # is not the same claim: the provider refuses an intent the customer completed in the
        # meantime, and the succeeded webhook can land before this reload, so reading the absence
        # of processing as success would unlock an invoice that has just been paid.
        return result unless payment.reload.failed?

        unlock_invoice

        result
      end

      private

      attr_reader :payment

      delegate :payable, to: :payment

      # Scoped to the read on purpose: a rejected key, a revoked permission or a missing intent
      # reads the same way an hour from now, so it means "do nothing" rather than a job in the dead
      # set every hour. Rate limits and dropped connections say nothing about the intent and travel
      # up to the job's `retry_on`. A failure to cancel is neither, and must not be logged as one.
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
        return false unless abandoned_at_redirect?
        return false if payable.payment_succeeded? || payable.voided? || payable.closed?
        # Cancelling would land a failed payment status on the invoice, and that resolves the
        # activation through Invoices::UpdateService. That flow has its own window and its own clock.
        !payment.gated_subscription_activation?
      end

      def abandoned_at_redirect?
        payment.status == "requires_action" &&
          payment.processing? &&
          payment.provider_payment_data&.dig("type") == "redirect_to_url" &&
          payment.updated_at.between?(RECOVERY_WINDOW.ago, ABANDONED_PERIOD.ago)
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
