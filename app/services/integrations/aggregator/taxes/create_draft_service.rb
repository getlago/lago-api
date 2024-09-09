# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      class CreateDraftService < BaseService
        def action_path
          "v1/#{provider}/draft_invoices"
        end

        def call
          return result unless integration
          return result unless integration.type == 'Integrations::AnrokIntegration'

          response = http_client.post_with_response(payload, headers)
          body = JSON.parse(response.body)

          process_response(body)

          result
        rescue LagoHttpClient::HttpError => e
          code = code(e)
          message = message(e)

          result.service_failure!(code:, message:)
        end

        private

        def payload
          payload_service.create_draft_payload
        end
      end
    end
  end
end
