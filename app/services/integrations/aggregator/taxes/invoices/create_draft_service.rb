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
            return result unless integration.type == "Integrations::AnrokIntegration"

            throttle!(:anrok)

            response = http_client.post_with_response(payload, headers)
            body = parse_response(response)

            process_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError(e) if request_limit_error?(e)
            raise e if bad_gateway_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          end

          private

          def payload
            Integrations::Aggregator::Taxes::Invoices::Payload.new(
              integration:,
              invoice:,
              customer:,
              integration_customer:,
              fees:
            ).body
          end
        end
      end
    end
  end
end
