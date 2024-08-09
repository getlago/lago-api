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
            return result unless integration.type == 'Integrations::AnrokIntegration'

            response = http_client.post_with_response(payload, headers)
            body = JSON.parse(response.body)

            process_void_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          end

          private

          def payload
            [
              {
                'id' => invoice.id
              }
            ]
          end
        end
      end
    end
  end
end
