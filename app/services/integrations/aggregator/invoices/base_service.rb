# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class BaseService < Integrations::Aggregator::BaseService
        INVALID_LOGIN_ATTEMPT = "INVALID_LOGIN_ATTEMPT"

        def initialize(invoice:)
          @invoice = invoice

          super(integration:)
        end

        private

        attr_reader :invoice

        delegate :customer, to: :invoice, allow_nil: true

        def headers
          {
            "Connection-Id" => integration.connection_id,
            "Authorization" => "Bearer #{secret_key}",
            "Provider-Config-Key" => provider_key
          }
        end

        def integration
          return nil unless integration_customer

          integration_customer&.integration
        end

        def integration_customer
          @integration_customer ||= customer&.integration_customers&.accounting_kind&.first
        end

        def payload
          Integrations::Aggregator::Invoices::Payloads::Factory.new_instance(
            integration_customer:,
            invoice:
          )
        end

        def retryable_error?(http_error)
          server_error = http_error.error_code.to_i >= 500 || http_error.error_code.to_i == 424
          server_error && !invalid_login_attempt_error?(http_error)
        end

        def invalid_login_attempt_error?(http_error)
          http_error.error_body.include?(INVALID_LOGIN_ATTEMPT)
        end
      end
    end
  end
end
