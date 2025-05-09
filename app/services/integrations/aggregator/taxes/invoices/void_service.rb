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

            response = http_client.post_with_response(payload, headers)
            body = JSON.parse(response.body)

            process_void_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError(e) if request_limit_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          end

          private

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
