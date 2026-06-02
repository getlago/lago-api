# frozen_string_literal: true

module PaymentProviders
  class RefundPaymentService < BaseService
    Result = BaseResult[:payment, :refund]

    def initialize(payment:, reason: nil)
      @payment = payment
      @reason = reason
      super
    end

    def call
      result.payment = payment

      return result if payment.payment_provider.blank?
      return result if payment.provider_payment_id.blank?
      return existing_refund_result if existing_refund

      case payment.payment_provider.type
      when "PaymentProviders::StripeProvider"
        delegate_to(PaymentProviders::Stripe::Payments::RefundService)
      else
        # TODO(M4-providers): Adyen and GoCardless refund services land in
        # follow-up PRs; their case branches go here when the services exist.
        # TODO(M4-webhooks): emit `payment.refund_requires_action` outbound
        # webhook so ops can issue the refund manually for Cashfree,
        # Flutterwave, and Moneyhash (no PSP refund API integration).
        Rails.logger.info(
          "PaymentProviders::RefundPaymentService: PSP refund not supported for " \
          "#{payment.payment_provider.type} (payment #{payment.id}); skipping"
        )
      end

      result
    end

    private

    attr_reader :payment, :reason

    # M4 issues full-payment refunds, so a single Refund row per payment
    # is the contract — once a payment is refunded, we can't refund it
    # again regardless of reason or status. The PSP idempotency key in
    # the provider-specific service is the second layer of defense
    # against duplicate side effects.
    def existing_refund
      @existing_refund ||= Refund.find_by(payment_id: payment.id)
    end

    def existing_refund_result
      result.refund = existing_refund
      result
    end

    def delegate_to(service)
      provider_result = service.call!(payment:, reason:)
      result.refund = provider_result.refund
      result
    end
  end
end
