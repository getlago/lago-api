# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        class CreateDraftService < BaseService
          ADDRESS_RESOLVE_ERROR = "customerAddressCouldNotResolve"

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
            raise e if bad_gateway_error?(e)

            code = code(e)
            message = message(e)

            deliver_tax_error_webhook(customer:, code:, message:) if customer_address_error?(code)

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

          def customer_address_error?(code)
            code == ADDRESS_RESOLVE_ERROR
          end
        end
      end
    end
  end
end
