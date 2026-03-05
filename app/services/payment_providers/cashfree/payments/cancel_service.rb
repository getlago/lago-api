# frozen_string_literal: true

module PaymentProviders
  module Cashfree
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

          # Cashfree uses Payment Links, which can be cancelled via PATCH to expire the link.
          # The link_id is stored as provider_payment_id.
          # https://docs.cashfree.com/reference/cancel-payment-link
          headers = {
            "accept" => "application/json",
            "content-type" => "application/json",
            "x-client-id" => cashfree_payment_provider.client_id,
            "x-client-secret" => cashfree_payment_provider.client_secret,
            "x-api-version" => ::PaymentProviders::CashfreeProvider::API_VERSION
          }

          # Cashfree cancel link endpoint: POST /links/{link_id}/cancel
          client = LagoHttpClient::Client.new(
            "#{::PaymentProviders::CashfreeProvider::BASE_URL}/#{payment.provider_payment_id}/cancel"
          )
          client.post_with_response({}, headers)

          result
        rescue LagoHttpClient::HttpError => e
          # Link may already be paid, expired, or cancelled
          result.service_failure!(code: "cashfree_error", message: e.error_body)
        end

        private

        attr_reader :payment, :provider_customer

        delegate :customer, to: :provider_customer

        def cashfree_payment_provider
          @cashfree_payment_provider ||= payment_provider(customer)
        end
      end
    end
  end
end
