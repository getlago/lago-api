# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class AuthorizeService < BaseService
        Result = BaseResult[:stripe_payment_intent, :authorization]

        # The authorization is a manual-capture hold, which Stripe refuses for these types.
        # Card and Link can be held.
        NON_HOLDABLE_METHOD_TYPES = %w[sepa_debit us_bank_account bacs_debit boleto customer_balance].freeze

        def initialize(amount:, currency:, provider_customer:, payment_method:, unique_id:, metadata: {})
          @amount = amount
          @currency = currency
          @provider_customer = provider_customer
          @payment_method = payment_method
          @unique_id = unique_id
          @metadata = metadata

          super(provider_customer.payment_provider)
        end

        def call
          find_provider_method_id

          if payment_method_id.nil?
            return result.single_validation_failure!(
              field: :payment_method_id,
              error_code: "customer_has_no_payment_method"
            )
          end

          if NON_HOLDABLE_METHOD_TYPES.include?(payment_method_type)
            return result.single_validation_failure!(
              field: :payment_method_id,
              error_code: "payment_method_not_supported_for_authorization"
            )
          end

          payment_intent = create_payment_intent

          result.stripe_payment_intent = payment_intent
          result.authorization = authorization_payload(payment_intent)

          result
        rescue ::Stripe::StripeError => e
          result.provider_failure!(provider: payment_provider, error: e)
        ensure
          if payment_intent.present?
            PaymentProviders::CancelPaymentAuthorizationJob.perform_later(
              payment_provider: provider_customer.payment_provider, id: payment_intent.id
            )
          end
        end

        private

        # Only known for a stored payment method whose details came from Stripe. When it is unknown,
        # Stripe decides, as before.
        def payment_method_type
          return if payment_method.blank? || payment_method.details.blank?

          payment_method.details.with_indifferent_access[:type]
        end

        def find_provider_method_id
          @payment_method_id = if payment_method.present?
            payment_method.provider_method_id
          elsif provider_customer.payment_method_id.present?
            provider_customer.payment_method_id
          else
            # Cards only: the pre-authorization is a manual-capture hold, which bank debits cannot do
            PaymentProviderCustomers::Stripe::RetrieveLatestPaymentMethodService.call!(
              provider_customer:,
              types: %w[card]
            ).payment_method_id
          end
        end

        def create_payment_intent
          ::Stripe::PaymentIntent.create(
            {
              amount: stripe_amount,
              currency: currency.downcase,
              confirm: true,
              capture_method: "manual",
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

        # The amount comes from the request as is. When it is not an integer, Stripe rejects it, as before.
        def stripe_amount
          integer_amount = Integer(amount.to_s, 10, exception: false)

          if integer_amount.nil?
            amount
          else
            ::PaymentProviders::StripeProvider.to_stripe_amount(integer_amount, currency)
          end
        end

        # Stripe reads some currencies in hundredths: answer in the units of the request
        def authorization_payload(payment_intent)
          intent = payment_intent.to_hash
          payload = intent.slice(:id, :object, :amount, :amount_capturable, :status)

          %i[amount amount_capturable].each do |key|
            next unless payload.key?(key)

            payload[key] = ::PaymentProviders::StripeProvider.from_stripe_amount(payload[key], intent[:currency])
          end

          payload
        end

        attr_reader :amount, :currency, :provider_customer, :payment_method, :payment_method_id, :unique_id, :metadata
      end
    end
  end
end
