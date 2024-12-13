# frozen_string_literal: true

module PaymentProviders
  module Adyen
    module Payments
      class CreateService < BaseService
        PENDING_STATUSES = %w[AuthorisedPending Received].freeze
        SUCCESS_STATUSES = %w[Authorised SentForSettle SettleScheduled Settled Refunded].freeze
        FAILED_STATUSES = %w[Cancelled CaptureFailed Error Expired Refused].freeze

        def initialize(payment:)
          @payment = payment
          @invoice = payment.payable
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment

          adyen_result = create_adyen_payment

          if adyen_result.status > 400
            result.error_message = adyen_result.response["message"]
            result.error_code = adyen_result.response["errorType"]
            return result
          end

          payment.provider_payment_data = adyen_result.response["pspReference"]
          payment.status = adyen_result.response["resultCode"]
          payment.save!

          result.payment_status = payment_status_mapping(payment.status)
          result.payment = payment
          result
        rescue ::Adyen::AuthenticationError, ::Adyen::ValidationError => e
          result.error_message = e.msg
          result.error_code = e.code
          result.payment_status = :failed
          result
        rescue ::Adyen::AdyenError => e
          result.error_message = e.msg
          result.error_code = e.code
          result.payment_status = :failed
          result.service_failure!(code: "adyen_error", message: "#{e.code}: #{e.msg}")
        rescue Faraday::ConnectionFailed => e
          raise Invoices::Payments::ConnectionError, e
        end

        private

        attr_reader :payment, :invoice, :provider_customer

        delegate :payment_provider, :customer, to: :provider_customer

        def client
          @client ||= ::Adyen::Client.new(
            api_key: payment_provider.api_key,
            env: payment_provider.environment,
            live_url_prefix: payment_provider.live_prefix
          )
        end

        def success_redirect_url
          payment_provider.success_redirect_url.presence || ::PaymentProviders::AdyenProvider::SUCCESS_REDIRECT_URL
        end

        def update_payment_method_id
          result = client.checkout.payments_api.payment_methods(
            Lago::Adyen::Params.new(payment_method_params).to_h
          ).response

          payment_method_id = result["storedPaymentMethods"]&.first&.dig("id")
          provider_customer.update!(payment_method_id:) if payment_method_id
        end

        def create_adyen_payment
          update_payment_method_id

          client.checkout.payments_api.payments(
            Lago::Adyen::Params.new(payment_params).to_h,
            headers: {"idempotency-key" => "payment-#{payment.id}"}
          )
        end

        def payment_method_params
          {
            merchantAccount: payment_provider.merchant_account,
            shopperReference: provider_customer.provider_customer_id
          }
        end

        def payment_params
          prms = {
            amount: {
              currency: invoice.currency.upcase,
              value: invoice.total_amount_cents
            },
            reference: invoice.number,
            paymentMethod: {
              type: "scheme",
              storedPaymentMethodId: provider_customer.payment_method_id
            },
            shopperReference: provider_customer.provider_customer_id,
            merchantAccount: payment_provider.merchant_account,
            shopperInteraction: "ContAuth",
            recurringProcessingModel: "UnscheduledCardOnFile"
          }
          prms[:shopperEmail] = customer.email if customer.email
          prms
        end

        def payment_status_mapping(payment_status)
          return :pending if PENDING_STATUSES.include?(payment_status)
          return :succeeded if SUCCESS_STATUSES.include?(payment_status)
          return :failed if FAILED_STATUSES.include?(payment_status)

          payment_status
        end
      end
    end
  end
end
