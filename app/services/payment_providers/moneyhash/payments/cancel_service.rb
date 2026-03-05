# frozen_string_literal: true

module PaymentProviders
  module Moneyhash
    module Payments
      class CancelService < BaseService
        include ::Customers::PaymentProviderFinder

        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          # Moneyhash payment intents can be voided via the API
          # https://docs.moneyhash.io/docs/void-payment-intent
          headers = {
            "Content-Type" => "application/json",
            "x-Api-Key" => moneyhash_payment_provider.api_key
          }

          client = LagoHttpClient::Client.new(
            "#{::PaymentProviders::MoneyhashProvider.api_base_url}/api/v1.1/payments/intent/#{payment.provider_payment_id}/void/"
          )
          client.post_with_response({}, headers)

          result
        rescue LagoHttpClient::HttpError => e
          # Payment intent may already be processed, voided, or in a non-cancelable state
          result.service_failure!(code: "moneyhash_error", message: e.error_body)
        end

        private

        attr_reader :payment, :provider_customer

        delegate :customer, to: :provider_customer

        def moneyhash_payment_provider
          @moneyhash_payment_provider ||= payment_provider(customer)
        end
      end
    end
  end
end
