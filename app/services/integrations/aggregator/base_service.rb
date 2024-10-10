# frozen_string_literal: true

require 'lago_http_client'

module Integrations
  module Aggregator
    class BaseService < BaseService
      BASE_URL = 'https://api.nango.dev/'
      REQUEST_LIMIT_ERROR_CODE = 'SSS_REQUEST_LIMIT_EXCEEDED'

      def initialize(integration:, options: {})
        @integration = integration
        @options = options

        super
      end

      def action_path
        raise NotImplementedError
      end

      private

      attr_reader :integration, :options

      # NOTE: Extend it with other providers if needed
      def provider
        case integration.type
        when 'Integrations::NetsuiteIntegration'
          'netsuite'
        when 'Integrations::XeroIntegration'
          'xero'
        when 'Integrations::AnrokIntegration'
          'anrok'
        when 'Integrations::HubspotIntegration'
          'hubspot'
        end
      end

      def provider_key
        case integration.type
        when 'Integrations::NetsuiteIntegration'
          'netsuite-tba'
        when 'Integrations::XeroIntegration'
          'xero'
        when 'Integrations::AnrokIntegration'
          'anrok'
        when 'Integrations::HubspotIntegration'
          'hubspot'
        end
      end

      def http_client
        LagoHttpClient::Client.new(endpoint_url)
      end

      def endpoint_url
        "#{BASE_URL}#{action_path}"
      end

      def headers
        {
          'Connection-Id' => integration.connection_id,
          'Authorization' => "Bearer #{secret_key}"
        }
      end

      def deliver_error_webhook(customer:, code:, message:)
        SendWebhookJob.perform_later(
          webhook_code,
          customer,
          provider:,
          provider_code: integration.code,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def deliver_integration_error_webhook(integration:, code:, message:)
        SendWebhookJob.perform_later(
          'integration.provider_error',
          integration,
          provider:,
          provider_code: integration.code,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def deliver_tax_error_webhook(customer:, code:, message:)
        SendWebhookJob.perform_later(
          'customer.tax_provider_error',
          customer,
          provider:,
          provider_code: integration.code,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def secret_key
        ENV['NANGO_SECRET_KEY']
      end

      def webhook_code
        case provider
        when 'hubspot'
          'customer.crm_provider_error'
        else
          'customer.accounting_provider_error'
        end
      end

      def code(error)
        json = error.json_message
        json['type'].presence || json.dig('error', 'payload', 'name').presence || json.dig('error', 'code')
      end

      def message(error)
        json = error.json_message
        json.dig('payload', 'message').presence ||
          json.dig('error', 'payload', 'message').presence ||
          json.dig('error', 'message')
      end

      def request_limit_error?(http_error)
        return false unless http_error.error_code.to_i == 500

        http_error.error_body.include?(REQUEST_LIMIT_ERROR_CODE)
      end
    end
  end
end
