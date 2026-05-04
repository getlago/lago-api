# frozen_string_literal: true

module PaymentProviders
  module Paystack
    module Payments
      class CreateService < BaseService
        def initialize(payment:, reference:, metadata:)
          @payment = payment
          @reference = reference
          @metadata = metadata
          @provider_customer = payment.payment_provider_customer

          super
        end

        def call
          result.payment = payment
          return unsupported_currency_result unless supported_currency?
          return create_hosted_checkout_payment if authorization_code.blank?

          paystack_result = client.charge_authorization(charge_authorization_payload)
          paystack_payment = paystack_result["data"] || {}
          status = paystack_payment["status"].presence || "failed"

          payment.provider_payment_id = paystack_payment["id"]&.to_s || paystack_payment["reference"]
          payment.status = status
          payment.payable_payment_status = paystack_payment_provider.payable_payment_status(status)
          payment.provider_payment_data = provider_payment_data(paystack_payment)
          payment.save!

          update_payment_method(paystack_payment["authorization"]) if payment.payable_payment_status == "succeeded"
          return result if payment.payable_payment_status != "failed"

          prepare_failed_result(
            error_message: paystack_payment["gateway_response"].presence || paystack_result["message"].presence || "Paystack payment failed",
            error_code: status
          )
        rescue PaymentProviders::Paystack::Client::Error => e
          prepare_failed_result(error_message: e.message, error_code: e.code)
        rescue LagoHttpClient::HttpError => e
          raise Invoices::Payments::RateLimitError, e if e.error_code.to_i == 429
          raise Invoices::Payments::ConnectionError, e if e.error_code.to_i >= 500

          prepare_failed_result(error_message: e.error_body, error_code: e.error_code)
        end

        private

        attr_reader :payment, :reference, :metadata, :provider_customer

        def create_hosted_checkout_payment
          paystack_result = client.initialize_transaction(hosted_checkout_payload)
          paystack_payment = paystack_result["data"] || {}

          payment.status = "requires_action"
          payment.payable_payment_status = "processing"
          payment.provider_payment_data = provider_payment_data(paystack_payment)
          payment.save!

          SendWebhookJob.perform_later("payment.requires_action", payment)

          result
        end

        def charge_authorization_payload
          {
            amount: payment.amount_cents,
            email: customer.email&.strip&.split(",")&.first,
            authorization_code: authorization_code,
            reference: reference,
            currency: payment.amount_currency.upcase,
            metadata: enriched_metadata.to_json
          }
        end

        def hosted_checkout_payload
          {
            amount: payment.amount_cents,
            email: customer.email&.strip&.split(",")&.first,
            reference: reference,
            currency: payment.amount_currency.upcase,
            callback_url: success_redirect_url,
            metadata: enriched_metadata.to_json
          }
        end

        def enriched_metadata
          metadata.merge(
            lago_payment_id: payment.id,
            lago_payable_id: payment.payable_id,
            lago_payable_type: payment.payable_type,
            lago_customer_id: payment.payable.customer_id,
            lago_organization_id: payment.payable.organization_id,
            lago_billing_entity_id: payment.payable.billing_entity.id,
            lago_payment_provider_id: paystack_payment_provider.id,
            lago_payment_provider_code: paystack_payment_provider.code,
            payment_type: "recurring"
          )
        end

        def authorization_code
          if payment.organization.feature_flag_enabled?(:multiple_payment_methods)
            payment.payment_method&.provider_method_id
          else
            provider_customer.payment_method_id.presence || provider_customer.authorization_code
          end
        end

        def provider_payment_data(paystack_payment)
          {
            reference: paystack_payment["reference"],
            gateway_response: paystack_payment["gateway_response"],
            channel: paystack_payment["channel"],
            authorization_url: paystack_payment["authorization_url"],
            access_code: paystack_payment["access_code"]
          }.compact
        end

        def update_payment_method(authorization)
          return unless reusable_card_authorization?(authorization)

          PaymentProviderCustomers::PaystackService.new.update_payment_method(
            organization_id: payment.organization_id,
            customer_id: customer.id,
            payment_method_id: authorization["authorization_code"],
            metadata: enriched_metadata.stringify_keys,
            card_details: card_details(authorization)
          ).raise_if_error!
        end

        def reusable_card_authorization?(authorization)
          authorization.present? &&
            authorization["authorization_code"].present? &&
            authorization["reusable"] == true &&
            authorization["channel"] == "card"
        end

        def card_details(authorization)
          {
            type: "card",
            last4: authorization["last4"],
            brand: authorization["brand"].presence || authorization["card_type"],
            expiration_month: authorization["exp_month"],
            expiration_year: authorization["exp_year"],
            issuer: authorization["bank"],
            country: authorization["country_code"]
          }.compact
        end

        def prepare_failed_result(error_message:, error_code:, reraise: false)
          result.error_message = error_message
          result.error_code = error_code
          result.reraise = reraise

          payment.update!(status: "failed", payable_payment_status: "failed")

          result.service_failure!(code: "paystack_error", message: error_message)
        end

        def customer
          payment.customer
        end

        def client
          @client ||= PaymentProviders::Paystack::Client.new(payment_provider: paystack_payment_provider)
        end

        def paystack_payment_provider
          @paystack_payment_provider ||= provider_customer.payment_provider
        end

        def success_redirect_url
          paystack_payment_provider.success_redirect_url.presence ||
            ::PaymentProviders::PaystackProvider::SUCCESS_REDIRECT_URL
        end

        def supported_currency?
          PaymentProviders::PaystackProvider.supported_currency?(payment.amount_currency)
        end

        def unsupported_currency_result
          prepare_failed_result(
            error_message: "Currency #{payment.amount_currency.upcase} is not supported by Paystack",
            error_code: "unsupported_currency"
          )
        end
      end
    end
  end
end
