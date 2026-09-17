# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class RetrieveService < BaseService
        Result = BaseResult[:status, :payment_method_type]

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          intent = ::Stripe::PaymentIntent.retrieve(
            {id: payment.provider_payment_id, expand: ["payment_method"]},
            {api_key: payment.payment_provider.secret_key}
          )

          result.status = intent.status
          result.payment_method_type = intent.payment_method&.type
          result
        end

        private

        attr_reader :payment
      end
    end
  end
end
