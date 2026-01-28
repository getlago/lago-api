# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Customers
      class FetchDefaultPaymentMethodService < BaseService
        Result = BaseResult[:payment_method]

        def initialize(provider_customer:)
          @provider_customer = provider_customer

          super
        end

        def call
          return result unless provider_customer.provider_customer_id?

          payment_method_id = PaymentProviderCustomers::Stripe::RetrieveLatestPaymentMethodService.call!(
            provider_customer:
          ).payment_method_id

          return result unless payment_method_id

          payment_method = PaymentMethods::CreateFromProviderService.call(
            customer: provider_customer.customer,
            params: {provider_payment_methods: provider_customer.provider_payment_methods},
            provider_method_id: payment_method_id,
            payment_provider_id: provider_customer.payment_provider_id,
            payment_provider_customer: provider_customer,
            details: payment_method_details(payment_method_id:)
          ).payment_method

          result.payment_method = payment_method

          result
        end

        private

        attr_reader :provider_customer

        def payment_method_details(payment_method_id:)
          pm = ::Stripe::PaymentMethod.retrieve(
            payment_method_id,
            {api_key: provider_customer.payment_provider.secret_key}
          )

          PaymentMethods::CardDetails.new(
            type: pm.type,
            last4: pm.card&.last4,
            brand: pm.card&.display_brand,
            expiration_month: pm.card&.exp_month,
            expiration_year: pm.card&.exp_year,
            card_holder_name: nil,
            issuer: nil
          ).to_h
        end
      end
    end
  end
end
