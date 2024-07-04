# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class CreateService < BaseService
          def action_path
            "v1/#{provider}/finalized_invoices"
          end

          def call
            return result unless integration
            return result unless integration.type == 'Integrations::AnrokIntegration'

            response = http_client.post_with_response(payload, headers)
            body = JSON.parse(response.body)

            process_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            error = e.json_message
            code = error['type']
            message = error.dig('payload', 'message')

            result.service_failure!(code:, message:)
          end

          private

          def payload
            payload = Integrations::Aggregator::Taxes::Invoices::Payload.new(
              integration:,
              invoice:,
              customer:,
              fees:
            ).body

            invoice_data = payload.first
            invoice_data['id'] = invoice.id

            [invoice_data]
          end
        end
      end
    end
  end
end
