# frozen_string_literal: true

module Invoices
  module Payments
    module PaymentProviders
      class FlutterwaveService < BaseService
        include Customers::PaymentProviderFinder

        def initialize(invoice:)
          @invoice = invoice

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

        attr_reader :invoice

        delegate :organization, :customer, to: :invoice

        def payment_url
          response = create_checkout_session

          response["data"]["link"]
        end

        def create_checkout_session
          body = {
            amount: invoice.total_amount_cents / 100.0,
            tx_ref: "lago_invoice_#{invoice.id}",
            currency: invoice.currency.upcase,
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
            title: "#{organization.name} - Invoice Payment",
            description: "Payment for Invoice ##{invoice.number}",
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
            lago_invoice_id: invoice.id,
            lago_organization_id: organization.id,
            lago_invoice_number: invoice.number
          }
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
          return unless invoice.organization.webhook_endpoints.any?

          SendWebhookJob.perform_later(
            "invoice.payment_failure",
            invoice,
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
end
