# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateService < BaseService
        def action_path
          "v1/#{provider}/invoices"
        end

        def call
          return result unless integration
          return result unless integration.sync_invoices
          return result unless invoice.finalized?
          return result unless fallback_item

          response = http_client.post_with_response(payload('invoice'), headers)
          result.external_id = JSON.parse(response.body)

          IntegrationResource.create!(
            integration:,
            external_id: result.external_id,
            syncable_id: invoice.id,
            syncable_type: 'Invoice',
            resource_type: :invoice,
          )

          result
        rescue LagoHttpClient::HttpError => e
          error = e.json_message
          code = error['type']
          message = error.dig('payload', 'message')

          deliver_error_webhook(customer:, code:, message:)

          raise e
        end

        def call_async
          return result.not_found_failure!(resource: 'invoice') unless invoice

          ::Integrations::Aggregator::Invoices::CreateJob.perform_later(invoice:)

          result.invoice_id = invoice.id
          result
        end
      end
    end
  end
end
