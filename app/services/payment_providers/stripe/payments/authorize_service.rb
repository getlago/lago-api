# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class AuthorizeService < BaseService
        Result = BaseResult[:stripe_payment_intent]

        def initialize(amount:, currency:, provider_customer:, unique_id:, metadata: {})
          @amount = amount
          @currency = currency
          @provider_customer = provider_customer
          @payment_method_id = provider_customer.payment_method_id
          @unique_id = unique_id
          @metadata = metadata

          super(provider_customer.payment_provider)
        end

        def call
          if payment_method_id.blank?
            # If the customer doesn't have a payment_method_id on Lago, we check on Stripe before returning the error,
            # because it could be that it was just added and the webhook wasn't processed yet
            # The preauth api call requires a payment_method_id
            latest_id = PaymentProviderCustomers::Stripe::RetrieveLatestPaymentMethodService.call!(provider_customer:).payment_method_id

            if latest_id
              @payment_method_id = latest_id
            else
              return result.single_validation_failure!(field: :payment_method_id, error_code: "customer_has_no_payment_method")
            end
          end

          pi = create_payment_intent

          result.stripe_payment_intent = pi

          result
        rescue ::Stripe::StripeError => e
          result.provider_failure!(provider: payment_provider, error: e)
        ensure
          if pi
            PaymentProviders::CancelPaymentAuthorizationJob.perform_later(
              payment_provider: provider_customer.payment_provider, id: pi.id
            )
          end
        end

        private

        def create_payment_intent
          ::Stripe::PaymentIntent.create(
            {
              amount:,
              currency: currency.downcase,
              confirm: true,
              payment_method_options: {
                card: {
                  capture_method: "manual"
                }
              },
              customer: provider_customer.provider_customer_id,
              payment_method: payment_method_id,
              description: "Pre-authorization for subscription",
              metadata:,
              return_url: payment_provider.success_redirect_url,
              automatic_payment_methods: {
                enabled: true,
                allow_redirects: "never"
              }
            },
            {
              api_key:,
              idempotency_key: "auth-#{provider_customer.id}-#{unique_id}"
            }
          )
        end

        attr_reader :amount, :currency, :provider_customer, :payment_method_id, :unique_id, :metadata
      end
    end
  end
end
