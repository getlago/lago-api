# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class CancelService < BaseService
        Result = BaseResult

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          ::Stripe::PaymentIntent.cancel(
            payment.provider_payment_id,
            {cancellation_reason: :abandoned},
            {api_key: payment.payment_provider.secret_key}
          )

          result
        rescue ::Stripe::InvalidRequestError => e
          # Best-effort cancel: the payment intent has advanced to a non-cancelable
          # state (succeeded, processing, already canceled, etc.). Log and treat as
          # a successful no-op — the caller (timeout/expiration flow) should not
          # block on PSP-side cleanup.
          Rails.logger.info("Stripe payment intent not cancelable for payment #{payment.id}: #{e.message}")
          result
        end

        private

        attr_reader :payment
      end
    end
  end
end
