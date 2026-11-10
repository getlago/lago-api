# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class CreateDraftService < BaseService
          SERVER_ERROR_CODES = [500, 503, 504].freeze

          # NOTE: raise_on_server_error lets a caller that retries (the wallet refresh job) tell a
          #       temporary provider 5xx apart from a tax error. Other callers keep the service failure.
          def initialize(invoice:, fees: nil, raise_on_server_error: false)
            @raise_on_server_error = raise_on_server_error

            super(invoice:, fees:)
          end

          def action_name
            case provider
            when "anrok"
              "anrok-create-ephemeral-transaction"
            when "avalara"
              "request-tax-draft-invoice"
            end
          end

          def call
            return result unless integration
            return result unless ::Integrations::BaseIntegration::INTEGRATION_TAX_TYPES.include?(integration.type)
            return no_taxable_fees_result if taxable_fees.empty?

            body = if cache_taxes?
              DraftTaxesCacheService.new(integration:, payload:).call { request_taxes }
            else
              request_taxes
            end

            process_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError.new(e) if request_limit_error?(e)
            raise Integrations::Aggregator::BadGatewayError.new(e.error_body, e.uri) if bad_gateway_error?(e)
            raise Integrations::Aggregator::TaskInProgressError if task_in_progress_error?(e)
            raise Integrations::Aggregator::TaskExpiredError if task_expired_error?(e)
            raise Integrations::Aggregator::OrchestratorFailureError if orchestrator_failure_error?(e)
            raise Integrations::Aggregator::ServerError, "#{e.error_code}: #{e.error_body}" if server_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          rescue Net::ReadTimeout, Net::OpenTimeout, OpenSSL::SSL::SSLError => e
            raise Integrations::Aggregator::TimeoutError, e.message
          end

          private

          attr_reader :raise_on_server_error

          def server_error?(http_error)
            raise_on_server_error && SERVER_ERROR_CODES.include?(http_error.error_code.to_i)
          end

          # NOTE: Throttling happens here, so an answer served from the cache doesn't use up the
          #       provider rate limit.
          def request_taxes
            throttle!(:anrok, :avalara)

            response = trigger_action(payload)
            parse_response(response)
          end

          # NOTE: Only Anrok draft taxes are cached, see DraftTaxesCacheService.
          def cache_taxes?
            integration.type.to_s == "Integrations::AnrokIntegration"
          end

          def payload
            @payload ||= Integrations::Aggregator::Taxes::Invoices::Payloads::Factory.new_instance(
              integration:,
              invoice:,
              customer:,
              integration_customer:,
              fees: payload_fees
            ).body
          end
        end
      end
    end
  end
end
