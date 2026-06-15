# frozen_string_literal: true

module PaymentProviders
  class UpdatePaymentReferenceService < BaseService
    Result = BaseResult[:payment]

    def initialize(payment:)
      @payment = payment
      super
    end

    def call
      result.payment = payment

      return result if payment.payment_provider.blank?
      return result if payment.provider_payment_id.blank?

      case payment.payment_provider.type
      when "PaymentProviders::StripeProvider"
        delegate_to(PaymentProviders::Stripe::Payments::UpdateReferenceService)
      when "PaymentProviders::AdyenProvider"
        delegate_to(PaymentProviders::Adyen::Payments::UpdateReferenceService)
      when "PaymentProviders::GocardlessProvider"
        delegate_to(PaymentProviders::Gocardless::Payments::UpdateReferenceService)
      else
        # Cashfree, Flutterwave, and Moneyhash don't expose a metadata-update
        # API surface in their integrations. Reconciliation on those providers
        # continues to rely on the payment id and the customer-side dashboard;
        # the gap is documented and accepted.
        Rails.logger.info(
          "PaymentProviders::UpdatePaymentReferenceService: PSP reference update " \
          "not supported for #{payment.payment_provider.type} (payment #{payment.id}); skipping"
        )
      end

      result
    end

    private

    attr_reader :payment

    def delegate_to(service)
      service.call!(payment:)
      result
    end
  end
end
