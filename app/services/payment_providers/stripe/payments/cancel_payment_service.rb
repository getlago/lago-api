# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class CancelPaymentService < BaseService
        Result = BaseResult

        def initialize(payment_provider:, payment_intent_id:)
          @payment_intent_id = payment_intent_id

          super(payment_provider)
        end

        def call
          ::Stripe::PaymentIntent.cancel(
            payment_intent_id,
            {},
            api_key: payment_provider.secret_key
          )

          result
        rescue ::Stripe::StripeError => e
          result.provider_failure!(provider: payment_provider, error: e)
        end

        private

        attr_reader :payment_intent_id
      end
    end
  end
end
