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

            throttle!(:anrok, :avalara)

            response = http_client.post_with_response(payload, headers)
            body = parse_response(response)

            process_response(body)

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError(e) if request_limit_error?(e)
            raise Integrations::Aggregator::BadGatewayError.new(e.error_body, e.uri) if bad_gateway_error?(e)

            code = code(e)
            message = message(e)

            result.service_failure!(code:, message:)
          end

          private

          def payload
            Integrations::Aggregator::Taxes::Invoices::Payloads::Factory.new_instance(
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
