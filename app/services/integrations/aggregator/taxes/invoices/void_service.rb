# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class VoidService < BaseService
          def action_path
            "v1/#{provider}/void_invoices"
          end

          def call
            return result unless integration
            return result unless ::Integrations::BaseIntegration::INTEGRATION_TAX_TYPES.include?(integration.type)
            return result if never_reported?

            response = http_client.post_with_response(payload, headers)
            body = JSON.parse(response.body)

            process_void_response(body)

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

          # NOTE: Only an invoice carrying no fee at all is left unreported, so it holds no
          #       transaction to void and the call would be answered with an error that lands on
          #       the customer as a tax webhook. A resource recorded against the tax integration
          #       is proof the create call did reach the provider, so such an invoice is voided
          #       whatever its fees look like now.
          def never_reported?
            taxable_fees.empty? && reported_resources.none?
          end

          def reported_resources
            invoice.integration_resources.where(integration:, resource_type: :invoice)
          end

          def payload
            case integration.type.to_s
            when "Integrations::AvalaraIntegration"
              [
                {
                  "company_code" => integration.company_code,
                  "id" => invoice.id
                }
              ]
            else
              [
                {
                  "id" => invoice.id
                }
              ]
            end
          end
        end
      end
    end
  end
end
