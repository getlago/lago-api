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

            throttle!(:anrok)

            response = http_client.post_with_response(payload, headers)
            body = JSON.parse(response.body)

            process_response(body)
            assign_external_customer_id

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError(e) if request_limit_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          end

          private

          def payload
            payload_body = Integrations::Aggregator::Taxes::Invoices::Payload.new(
              integration:,
              invoice:,
              customer:,
              integration_customer:,
              fees:
            ).body

            invoice_data = payload_body.first
            invoice_data['id'] = invoice.id

            [invoice_data]
          end
        end
      end
    end
  end
end
