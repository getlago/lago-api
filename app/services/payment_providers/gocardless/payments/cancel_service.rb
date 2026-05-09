# frozen_string_literal: true

module PaymentProviders
  module Gocardless
    module Payments
      class CancelService < BaseService
        Result = BaseResult[:payment]

        def initialize(payment:)
          @payment = payment
          super
        end

        def call
          gocardless_result = client.payments.cancel(payment.provider_payment_id)

          payment.status = gocardless_result.status
          payment.payable_payment_status = payment.payment_provider.determine_payment_status(payment.status)
          payment.save!

          result.payment = payment
          result
        rescue GoCardlessPro::InvalidStateError => e
          # Best-effort cancel: the payment is in a non-cancelable state
          # (already submitted, paid out, cancelled, etc.). Log and treat as a
          # successful no-op so the caller (timeout/expiration flow) does not
          # block on PSP-side cleanup. The Payment record is left untouched;
          # the webhook for the prior state transition will land its true
          # state.
          Rails.logger.info("GoCardless payment not cancelable for payment #{payment.id}: #{e.message}")
          result
        end

        private

        attr_reader :payment

        def client
          @client ||= GoCardlessPro::Client.new(
            access_token: payment.payment_provider.access_token,
            environment: payment.payment_provider.environment
          )
        end
      end
    end
  end
end
