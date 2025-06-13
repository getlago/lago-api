# frozen_string_literal: true

module PaymentRequests
  module Payments
    class FlutterwaveService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(payable:)
        @payable = payable

        super
      end

      def call
        result.payment_url = payment_url
        result
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(e)

        result.service_failure!(code: "action_script_runtime_error", message: e.message)
      end

      private

      attr_reader :payable

      delegate :organization, :customer, to: :payable

      def payment_url
        response = create_checkout_session

        response["data"]["link"]
      end

      def create_checkout_session
        body = {
          amount: payable.total_amount_cents / 100.0,
          tx_ref: "lago_payment_request_#{payable.id}",
          currency: payable.currency.upcase,
          redirect_url: success_redirect_url,
          customer: customer_params,
          customizations: customizations_params,
          configuration: configuration_params,
          meta: meta_params
        }
        http_client.post_with_response(body, headers)
      end

      def customer_params
        {
          email: customer.email,
          phone_number: customer.phone || "",
          name: customer.name || customer.email
        }
      end

      def customizations_params
        {
          title: "#{organization.name} - Payment Request",
          description: "Payment for invoices: #{invoice_numbers}",
          logo: organization.logo_url
        }.compact
      end

      def configuration_params
        {
          session_duration: 30
        }
      end

      def meta_params
        {
          lago_customer_id: customer.id,
          lago_payment_request_id: payable.id,
          lago_organization_id: organization.id,
          lago_invoice_ids: payable.invoices.pluck(:id).join(",")
        }
      end

      def invoice_numbers
        payable.invoices.pluck(:number).join(", ")
      end

      def success_redirect_url
        flutterwave_payment_provider.success_redirect_url.presence ||
          PaymentProviders::FlutterwaveProvider::SUCCESS_REDIRECT_URL
      end

      def flutterwave_payment_provider
        @flutterwave_payment_provider ||= payment_provider(customer)
      end

      def headers
        {
          "Authorization" => "Bearer #{flutterwave_payment_provider.secret_key}",
          "Content-Type" => "application/json",
          "Accept" => "application/json"
        }
      end

      def http_client
        @http_client ||= LagoHttpClient::Client.new(flutterwave_payment_provider.api_url)
      end

      def deliver_error_webhook(http_error)
        return unless payable.organization.webhook_endpoints.any?

        SendWebhookJob.perform_later(
          "payment_request.payment_failure",
          payable,
          provider_customer_id: flutterwave_customer&.provider_customer_id,
          provider_error: {
            message: http_error.message,
            error_code: http_error.code
          }
        )
      end

      def flutterwave_customer
        @flutterwave_customer ||= customer.flutterwave_customer
      end
    end
  end
end
