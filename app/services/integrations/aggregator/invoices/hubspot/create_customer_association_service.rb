# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Hubspot
        class CreateCustomerAssociationService < BaseService
          def action_name
            "set-association"
          end

          def call
            return result if !integration || !integration.sync_invoices || !payload.integration_invoice

            Integrations::Hubspot::Invoices::DeployObjectService.call(integration:)

            throttle!(:hubspot)

            trigger_action(payload.customer_association_body)

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError.new(e) if request_limit_error?(e)

            code = code(e)
            message = message(e)

            deliver_error_webhook(customer:, code:, message:)

            raise e
          rescue Integrations::Aggregator::BasePayload::Failure => e
            deliver_error_webhook(customer:, code: e.code, message: e.code.humanize)
          end
        end
      end
    end
  end
end
