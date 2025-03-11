# frozen_string_literal: true

module PaymentProviderCustomers
  module Stripe
    class RetrieveLatestPaymentMethodService < BaseService
      Result = BaseResult[:payment_method_id]

      def initialize(provider_customer:)
        @provider_customer = provider_customer
        super
      end

      def call
        # We use limit: 10 just in case for some (wrong) reason the customer has a very high number of payment method
        list = ::Stripe::Customer.list_payment_methods(provider_customer.provider_customer_id, {limit: 10}, api_key:)
        result.payment_method_id = list.data.filter { _1.type == "card" }.max_by { _1.created }.id
        result
      end

      private

      attr_reader :provider_customer, :payment_method_id

      def api_key
        provider_customer.payment_provider.secret_key
      end
    end
  end
end
