# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
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

          if result.success? && integration_customer.external_customer_id.blank?
            integration_customer.update!(external_customer_id: customer.external_id)
          end

          result
        rescue LagoHttpClient::HttpError => e
          code = code(e)
          message = message(e)

          result.service_failure!(code:, message:)
        end

        private

        def payload
          payload_service.create_service_payload
        end
      end
    end
  end
end
