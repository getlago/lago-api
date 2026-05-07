# frozen_string_literal: true

module PaymentProviders
  module Adyen
    module Payments
      class CancelService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          adyen_result = client.checkout.modifications_api.cancel_authorised_payment_by_psp_reference(
            {merchantAccount: payment.payment_provider.merchant_account},
            payment.provider_payment_id
          )

          if adyen_result.status >= 400
            # Best-effort cancel: the payment is in a non-cancelable state
            # (already captured/cancelled, etc.). Log and treat as a successful
            # no-op so the caller (timeout/expiration flow) does not block on
            # PSP-side cleanup.
            Rails.logger.info(
              "Adyen payment not cancelable for payment #{payment.id}: " \
              "status=#{adyen_result.status} message=#{adyen_result.response["message"]}"
            )
            result.payment = payment
            return result
          end

          # Adyen's sync cancel response is an acknowledgment ("received"), not
          # a final state — Adyen confirms the actual cancellation
          # asynchronously via the CANCELLATION webhook. The Payment record
          # stays in its prior state until that webhook lands.
          result.payment = payment
          result
        rescue ::Adyen::ValidationError => e
          Rails.logger.info("Adyen payment not cancelable for payment #{payment.id}: #{e.msg}")
          result.payment = payment
          result
        rescue Faraday::ConnectionFailed => e
          raise Invoices::Payments::ConnectionError, e
        end

        private

        attr_reader :payment

        def client
          @client ||= ::Adyen::Client.new(
            api_key: payment.payment_provider.api_key,
            env: payment.payment_provider.environment,
            live_url_prefix: payment.payment_provider.live_prefix
          )
        end
      end
    end
  end
end
