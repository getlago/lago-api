# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      module Crm
        class CreateService < BaseService
          def call
            return result unless integration
            return result unless integration.sync_invoices
            return result unless invoice.finalized?

            Integrations::Hubspot::Invoices::DeployPropertiesService.call(integration:)

            response = http_client.post_with_response(payload.create_body, headers)
            body = JSON.parse(response.body)

            result.external_id = body['id']
            return result unless result.external_id

            IntegrationResource.create!(
              integration:,
              external_id: result.external_id,
              syncable_id: invoice.id,
              syncable_type: 'Invoice',
              resource_type: :invoice
            )

            result
          rescue LagoHttpClient::HttpError => e
            raise RequestLimitError(e) if request_limit_error?(e)

            code = code(e)
            message = message(e)

            deliver_error_webhook(customer:, code:, message:)

            result
          end

          def call_async(send_webhook: false)
            return result.not_found_failure!(resource: 'invoice') unless invoice

            SendWebhookJob.perform_later('invoice.resynced', invoice) if send_webhook

            ::Integrations::Aggregator::Invoices::Crm::CreateJob.perform_later(invoice:)

            result.invoice_id = invoice.id
            result
          end
        end
      end
    end
  end
end
