# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class CreateDraftService < BaseService
          def action_path
            "v1/#{provider}/draft_invoices"
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
            raise RequestLimitError(e) if request_limit_error?(e)
            raise Integrations::Aggregator::BadGatewayError.new(e.error_body, e.uri) if bad_gateway_error?(e)
            raise Integrations::Aggregator::TaskInProgressError if task_in_progress_error?(e)
            raise Integrations::Aggregator::TaskExpiredError if task_expired_error?(e)
            raise Integrations::Aggregator::OrchestratorFailureError if orchestrator_failure_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          rescue Net::ReadTimeout, Net::OpenTimeout, OpenSSL::SSL::SSLError => e
            raise Integrations::Aggregator::TimeoutError, e.message
          end

          private

          # NOTE: Throttling happens here, so an answer served from the cache doesn't use up the
          #       provider rate limit.
          def request_taxes
            throttle!(:anrok, :avalara)

            response = http_client.post_with_response(payload, headers)
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
