# frozen_string_literal: true

require "lago_http_client"

module Integrations
  module Aggregator
    class BaseService < BaseService
      BASE_URL = "https://api.nango.dev/"
      REQUEST_LIMIT_ERROR_CODE = "SSS_REQUEST_LIMIT_EXCEEDED"
      BAD_GATEWAY_ERROR = "502 Bad Gateway"
      TASK_IN_PROGRESS_PATTERN = /\bTask\b.*\bis in progress\b/
      TASK_EXPIRED_PATTERN = /\bTask\b.*\bexpired\b/
      ORCHESTRATOR_FAILURE_PATTERN = %r{POST https?://nango-orchestrator-svc\.nango/v1/immediate failed}
      # NOTE: Providers whose throttled jobs wait for the next rate limit window instead of backing off
      NEXT_WINDOW_RETRY_PROVIDERS = %i[quickbooks].freeze
      # NOTE: Intuit answers 429 with a ThrottlingFault (Error 3001, "message=ThrottleExceeded")
      QUICKBOOKS_RATE_LIMITED_PATTERN = /ThrottleExceeded|ThrottlingFault/
      # NOTE: Errors of a Nango read other than an HTTP status: an unparsable body or a connection failure
      LOOKUP_ERRORS = [
        JSON::ParserError,
        *LagoHttpClient::Client::TRANSIENT_ERROR_CLASSES,
        *LagoHttpClient::Client::CONNECT_FALLBACK_ERRORS
      ].uniq.freeze

      def self.retryable_errors
        [
          BadGatewayError, RequestLimitError, OutOfMemoryError,
          TaskInProgressError, TaskExpiredError, OrchestratorFailureError,
          ServerContentionError, TimeoutError
        ]
      end

      def initialize(integration:, options: {})
        @integration = integration
        @options = options

        super
      end

      # NOTE: Name of the Nango action script triggered through POST /action/trigger
      def action_name
        raise NotImplementedError
      end

      def action_path
        "action/trigger"
      end

      private

      attr_reader :integration, :options

      # NOTE: Extend it with other providers if needed
      def provider
        case integration.type
        when "Integrations::NetsuiteIntegration"
          "netsuite"
        when "Integrations::XeroIntegration"
          "xero"
        when "Integrations::AnrokIntegration"
          "anrok"
        when "Integrations::AvalaraIntegration"
          "avalara"
        when "Integrations::HubspotIntegration"
          "hubspot"
        when "Integrations::QuickbooksIntegration"
          "quickbooks"
        end
      end

      # The Nango provider config key, which can differ from Integrations::BaseIntegration#provider_key
      # (netsuite-tba for NetSuite, quickbooks-sandbox for a sandbox QuickBooks integration).
      def provider_key
        case integration.type
        when "Integrations::NetsuiteIntegration"
          "netsuite-tba"
        when "Integrations::XeroIntegration"
          "xero"
        when "Integrations::AnrokIntegration"
          "anrok"
        when "Integrations::AvalaraIntegration"
          Rails.env.production? ? "avalara" : "avalara-sandbox"
        when "Integrations::HubspotIntegration"
          "hubspot"
        when "Integrations::QuickbooksIntegration"
          integration.sandbox? ? "quickbooks-sandbox" : "quickbooks"
        end
      end

      def throttle!(*providers)
        providers.each do |provider_name|
          if provider == provider_name.to_s
            raise throttling_error(provider_name) \
              unless Throttling.for(provider_name.to_sym).check(:client, throttle_key)
          end
        end
      end

      def throttling_error(provider_name)
        if NEXT_WINDOW_RETRY_PROVIDERS.include?(provider_name.to_sym)
          return BaseService::NextWindowThrottlingError.new(provider_name:, retry_after: next_window_in(provider_name))
        end

        BaseService::ThrottlingError.new(provider_name:)
      end

      # The throttling gem counts in fixed buckets (Time.now.to_i / period): the next one opens at the
      # end of the shortest period. Limits are either one flat entry ({limit:, period:}) or named
      # entries ({minutely: {limit:, period:}}). Only the next-window providers reach this, and QuickBooks
      # has a single minutely limit, so the shortest period is the one that refused the call.
      def next_window_in(provider_name)
        limits = Throttling.limits[provider_name.to_sym]
        limits = {limit: limits} if limits.is_a?(Hash) && limits.key?(:period)
        periods = Array(limits&.values).filter_map { |limit| limit[:period].to_i if limit.is_a?(Hash) }.select(&:positive?)
        return BaseService::NextWindowThrottlingError::DEFAULT_RETRY_AFTER if periods.blank?

        period = periods.min
        (period - Time.current.to_i % period).seconds
      end

      def throttle_key
        # Hubspot, Xero and Avalara calls are throttled globally, NetSuite per client id and Anrok per api key.
        # Intuit counts QuickBooks calls per company, so they are throttled per company (realm id) and Nango
        # provider key, which keeps sandbox and production companies apart. Before the realm id is known,
        # the connection id is used. Every per-tenant value is digested.
        case provider
        when "netsuite"
          Digest::SHA2.hexdigest(integration.client_id)
        when "anrok"
          Digest::SHA2.hexdigest(integration.api_key)
        when "quickbooks"
          Digest::SHA2.hexdigest(integration.realm_id.present? ? "#{provider_key}:#{integration.realm_id}" : integration.connection_id)
        else
          provider.to_s
        end
      end

      def http_client
        LagoHttpClient::Client.new(endpoint_url, retries_on: [OpenSSL::SSL::SSLError])
      end

      def endpoint_url
        "#{BASE_URL}#{action_path}"
      end

      def headers
        {
          "Connection-Id" => integration.connection_id,
          "Authorization" => "Bearer #{secret_key}",
          "Provider-Config-Key" => provider_key
        }
      end

      # Never the response body, the headers, the URI or the connection id: they can hold OAuth credentials
      # or the QuickBooks realm id.
      def log_nango_failure(label, error, status: nil)
        details = {
          organization_id: integration.organization_id,
          provider_config_key: provider_key,
          error: error.class.name,
          status:
        }.compact

        Rails.logger.warn("#{label} #{details.to_json}")
      end

      def trigger_action(input)
        # NOTE: Every action shares the same URI, so errors are tagged with the action name to tell them apart
        Sentry.set_tags(nango_action: action_name) if defined?(Sentry)

        http_client.post_with_response({action_name:, input:}, headers)
      end

      def deliver_error_webhook(customer:, code:, message:)
        SendWebhookJob.perform_later(
          error_webhook_code,
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
          "integration.provider_error",
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
          "customer.tax_provider_error",
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
        ENV["NANGO_SECRET_KEY"]
      end

      def error_webhook_code
        case provider
        when "hubspot"
          "customer.crm_provider_error"
        when "avalara"
          "customer.tax_provider_error"
        else
          "customer.accounting_provider_error"
        end
      end

      def code(error)
        json = error.json_message
        safe_dig_str(json, "type") ||
          safe_dig_str(json, "error", "payload", "name") ||
          safe_dig_str(json, "error", "payload", "error", "code") ||
          safe_dig_str(json, "error", "code") ||
          "unexpected_error"
      end

      def message(error)
        json = error.json_message
        safe_dig_str(json, "payload", "message") ||
          safe_dig_str(json, "error", "payload", "message") ||
          safe_dig_str(json, "error", "payload", "error") ||
          safe_dig_str(json, "error", "payload", "error", "message") ||
          safe_dig_str(json, "error", "message") ||
          json.to_json
      end

      # Safe dig method for nested hashes as #dig breaks on non-Hash values
      def safe_dig_str(obj, *keys)
        value = keys.reduce(obj) { |o, k| o.is_a?(Hash) ? o[k].presence : nil }
        value.is_a?(String) ? value : nil
      end

      def request_limit_error?(http_error)
        http_error.error_body.include?(REQUEST_LIMIT_ERROR_CODE)
      end

      # Nango returns an action's upstream 429 inside its own error body, so the body is checked too.
      def quickbooks_rate_limited?(http_error)
        http_error.error_code.to_i == 429 || QUICKBOOKS_RATE_LIMITED_PATTERN.match?(http_error.error_body.to_s)
      end

      def bad_gateway_error?(http_error)
        http_error.error_code.to_s == "502" ||
          http_error.error_body.include?(BAD_GATEWAY_ERROR)
      end

      def task_in_progress_error?(http_error)
        code(http_error) == "action_script_failure" && TASK_IN_PROGRESS_PATTERN.match?(message(http_error))
      end

      def task_expired_error?(http_error)
        code(http_error) == "action_script_failure" && TASK_EXPIRED_PATTERN.match?(message(http_error))
      end

      def orchestrator_failure_error?(http_error)
        code(http_error) == "action_script_failure" && ORCHESTRATOR_FAILURE_PATTERN.match?(message(http_error))
      end

      def parse_response(response)
        JSON.parse(response.body)
      rescue JSON::ParserError
        if response.body.include?(BAD_GATEWAY_ERROR)
          # NOTE: Sometimes, Anrok is responding with an HTTP 200 with a payload containing a 502 error...
          raise(Integrations::Aggregator::BadGatewayError.new(response.body, http_client.uri))
        end

        raise
      end
    end
  end
end
