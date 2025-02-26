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
          @unique_id = unique_id
          @metadata = metadata

          super(provider_customer.payment_provider)
        end

        def call
          unless provider_customer.payment_method_id
            return result.single_validation_failure!(field: :payment_method_id, error_code: "customer_has_no_payment_method")
          end

          pi = create_payment_intent

          result.stripe_payment_intent = pi

          unless is_valid(pi)
            return result.third_party_failure!(third_party: "Stripe", error_code: "cannot_capture_amount", error_message: "The total amount was not captured.")
          end

          result
        rescue ::Stripe::StripeError => e
          result.third_party_failure!(third_party: "Stripe", error_message: e.message, error_code: e.code)
        ensure
          if pi
            PaymentProviders::CancelPaymentAuthorizationJob.perform_later(
              payment_provider: provider_customer.payment_provider, id: pi.id
            )
          end
        end

        private

        def is_valid(pi)
          pi.status == "requires_capture" && pi.amount == pi.amount_capturable
        end

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
              payment_method: provider_customer.payment_method_id,
              description: "Pre-authorization for subscription",
              metadata:
            },
            {
              api_key:,
              idempotency_key: "auth-#{provider_customer.id}-#{unique_id}"
            }
          )
        end

        attr_reader :amount, :currency, :provider_customer, :unique_id, :metadata
      end
    end
  end
end
