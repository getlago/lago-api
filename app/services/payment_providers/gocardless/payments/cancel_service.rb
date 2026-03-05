# frozen_string_literal: true

module PaymentProviders
  module Gocardless
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

          # GoCardless payments can only be cancelled before they are submitted to the bank.
          # Once submitted, the payment cannot be cancelled and must be refunded instead.
          # Statuses that allow cancellation: pending_customer_approval, pending_submission
          client.payments.cancel(payment.provider_payment_id)

          result
        rescue GoCardlessPro::InvalidStateError => e
          # Payment is already submitted/confirmed/paid_out and cannot be cancelled
          result.service_failure!(code: "gocardless_error", message: e.message)
        rescue GoCardlessPro::Error => e
          result.service_failure!(code: "gocardless_error", message: e.message)
        end

        private

        attr_reader :payment, :provider_customer

        delegate :payment_provider, to: :provider_customer

        def client
          @client ||= GoCardlessPro::Client.new(
            access_token: payment_provider.access_token,
            environment: payment_provider.environment
          )
        end
      end
    end
  end
end
