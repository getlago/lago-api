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
        # First, we try to get the customer default payment method
        payment_method_id = begin
          customer = ::Stripe::Customer.retrieve(provider_customer.provider_customer_id, request_options)
          customer["invoice_settings"]["default_payment_method"]
        rescue
          nil
        end

        # If no default, we'll try to get the latest card
        if payment_method_id.blank?
          payment_method_id = begin
            # We use limit: 10 just in case for some (wrong) reason the customer has a very high number of payment method
            list = ::Stripe::Customer.list_payment_methods(provider_customer.provider_customer_id, {limit: 10}, request_options)
            list.data.filter { _1.type == "card" }.max_by { _1.created }.id
          rescue
            nil
          end
        end

        result.payment_method_id = payment_method_id
        result
      end

      private

      attr_reader :provider_customer

      def request_options
        {
          api_key:,
          stripe_version: "2024-09-30.acacia"
        }
      end

      def api_key
        provider_customer.payment_provider.secret_key
      end
    end
  end
end
