# frozen_string_literal: true

module PaymentProviders
  module Stripe
    module Payments
      class GeneratePaymentUrlService < BaseService
        Result = BaseResult[:payment_url]

        def initialize(invoice:, payment_intent:)
          @invoice = invoice
          @payment_intent = payment_intent
          super(customer.stripe_customer.payment_provider)
        end

        def call
          res = ::Stripe::Checkout::Session.create(
            payment_url_payload,
            {
              api_key: payment_provider.secret_key,
              idempotency_key: "payment-intent-#{payment_intent.id}"
            }
          )

          result.payment_url = res["url"]

          result
        rescue ::Stripe::CardError, ::Stripe::InvalidRequestError, ::Stripe::AuthenticationError, ::Stripe::PermissionError => e
          result.third_party_failure!(third_party: "Stripe", error_code: e.code, error_message: e.message)
        end

        private

        attr_reader :invoice, :payment_intent

        delegate :organization, :customer, to: :invoice

        def payment_url_payload
          {
            line_items: [
              {
                quantity: 1,
                price_data: {
                  currency: invoice.currency.downcase,
                  unit_amount: invoice.total_due_amount_cents,
                  product_data: {
                    name: invoice.number
                  }
                }
              }
            ],
            mode: "payment",
            success_url: success_redirect_url,
            customer: customer.stripe_customer.provider_customer_id,
            payment_method_types: customer.stripe_customer.provider_payment_methods,
            expires_at: payment_intent.expires_at.to_i,
            payment_intent_data: {
              description:,
              setup_future_usage: setup_future_usage? ? "off_session" : nil,
              metadata: {
                lago_customer_id: customer.id,
                lago_invoice_id: invoice.id,
                invoice_issuing_date: invoice.issuing_date.iso8601,
                invoice_type: invoice.invoice_type,
                payment_type: "one-time"
              }
            }
          }
        end

        def description
          "#{organization.name} - Invoice #{invoice.number}"
        end

        # NOTE: Due to RBI limitation, all indians payment should be "on session". See: https://docs.stripe.com/india-recurring-payments
        # crypto payments don't support 'off_session'
        def setup_future_usage?
          return false if customer.country == "IN"
          return false if customer.stripe_customer.provider_payment_methods.include?("crypto")

          true
        end

        def success_redirect_url
          payment_provider.success_redirect_url.presence ||
            ::PaymentProviders::StripeProvider::SUCCESS_REDIRECT_URL
        end
      end
    end
  end
end
