# frozen_string_literal: true

module Payments
  class CancelService < BaseService
    Result = BaseResult[:payment]

    PROVIDER_CANCEL_SERVICES = {
      "PaymentProviders::StripeProvider" => PaymentProviders::Stripe::Payments::CancelService,
      "PaymentProviders::AdyenProvider" => PaymentProviders::Adyen::Payments::CancelService,
      "PaymentProviders::GocardlessProvider" => PaymentProviders::Gocardless::Payments::CancelService,
      "PaymentProviders::CashfreeProvider" => PaymentProviders::Cashfree::Payments::CancelService,
      "PaymentProviders::MoneyhashProvider" => PaymentProviders::Moneyhash::Payments::CancelService,
      "PaymentProviders::FlutterwaveProvider" => PaymentProviders::Flutterwave::Payments::CancelService
    }.freeze

    def initialize(payment:)
      @payment = payment

      super
    end

    def call
      result.payment = payment

      return result if payment.provider_payment_id.blank?
      return result if payment.payable_payment_status == "succeeded"

      cancel_service_class = PROVIDER_CANCEL_SERVICES[payment.payment_provider.class.name]

      if cancel_service_class.nil?
        return result.service_failure!(
          code: "unsupported_provider",
          message: "Payment cancellation not supported for #{payment.payment_provider.class.name}"
        )
      end

      cancel_service_class.call(payment:)
    end

    private

    attr_reader :payment
  end
end
