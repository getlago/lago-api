# frozen_string_literal: true

module PaymentProviderCustomers
  module Stripe
    class RetrieveLatestPaymentMethodService < BaseService
      Result = BaseResult[:payment_method_id]

      # types: the payment method types the fallback may return when the customer has no default.
      # Defaults to every type allowed on the customer that needs a setup (card, link, sepa_debit, etc.)
      def initialize(provider_customer:, types: nil)
        @provider_customer = provider_customer
        @types = types
        super
      end

      def call
        # First, we try to get the customer default payment method
        # We swallow all errors to run the second solution
        payment_method_id = begin
          customer = ::Stripe::Customer.retrieve(provider_customer.provider_customer_id, request_options)
          customer["invoice_settings"]["default_payment_method"]
        rescue
          nil
        end

        # If no default, we'll try to get the latest payment method of an allowed type
        # (card, but also link, sepa_debit, etc.), so a customer without any card can still be charged.
        # We also swallow all errors because this is "best effort". If no payment method is found, the caller service will handle it
        if payment_method_id.blank?
          payment_method_id = begin
            # We use limit: 10 just in case for some (wrong) reason the customer has a very high number of payment method
            list = ::Stripe::Customer.list_payment_methods(provider_customer.provider_customer_id, {limit: 10}, request_options)
            list.data.filter { allowed_types.include?(it.type) }.max_by { it.created }.id
          rescue
            nil
          end
        end

        result.payment_method_id = payment_method_id
        result
      end

      private

      attr_reader :provider_customer, :types

      def allowed_types
        types || provider_customer.provider_payment_methods_with_setup
      end

      def request_options
        {
          api_key:
        }
      end

      def api_key
        provider_customer.payment_provider.secret_key
      end
    end
  end
end
