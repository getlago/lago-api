# frozen_string_literal: true

module PaymentProviders
  module Adyen
    module Payments
      class CancelService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          # Adyen cancel via modifications API using the pspReference
          # https://docs.adyen.com/api-explorer/checkout/latest/post/cancels
          client.checkout.modifications_api.cancel_authorised_payment_by_psp_reference(
            payment.provider_payment_id,
            Lago::Adyen::Params.new(
              merchantAccount: payment_provider.merchant_account,
              reference: "cancel-#{payment.id}"
            ).to_h
          )

          result
        rescue ::Adyen::AdyenError, ::Adyen::AuthenticationError, ::Adyen::ValidationError => e
          result.service_failure!(code: "adyen_error", message: e.msg)
        end

        private

        attr_reader :payment, :provider_customer

        delegate :payment_provider, to: :provider_customer

        def client
          @client ||= ::Adyen::Client.new(
            api_key: payment_provider.api_key,
            env: payment_provider.environment,
            live_url_prefix: payment_provider.live_prefix
          )
        end
      end
    end
  end
end
