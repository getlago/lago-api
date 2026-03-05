# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class CancelService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment

          super(payment.payment_provider)
        end

        def call
          result.payment = payment

          ::Stripe::PaymentIntent.cancel(
            payment.provider_payment_id,
            {},
            {api_key:}
          )

          result
        rescue ::Stripe::InvalidRequestError => e
          # Payment intent may already be canceled, captured, or in a non-cancelable state
          result.service_failure!(code: "stripe_error", message: e.message)
        rescue ::Stripe::StripeError => e
          result.service_failure!(code: "stripe_error", message: e.message)
        end

        private

        attr_reader :payment
      end
    end
  end
end
