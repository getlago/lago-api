# frozen_String_literal: true

module PaymentProviderCustomers
  module Stripe
    class CheckPaymentMethodService < BaseService
      Result = BaseResult[:payment_method]

      def initialize(stripe_customer:, payment_method_id:)
        @stripe_customer = stripe_customer
        @payment_method_id = payment_method_id

        super
      end

      def call
        payment_method = ::Stripe::Customer
          .new(id: stripe_customer.provider_customer_id)
          .retrieve_payment_method(payment_method_id, {}, {api_key:})

        result.payment_method = payment_method
        result
      rescue ::Stripe::InvalidRequestError
        # NOTE: The payment method is no longer valid
        stripe_customer.update!(payment_method_id: nil)

        result.single_validation_failure!(field: :payment_method_id, error_code: "value_is_invalid")
      end

      private

      attr_reader :stripe_customer, :payment_method_id

      def api_key
        stripe_customer.payment_provider.secret_key
      end
    end
  end
end
