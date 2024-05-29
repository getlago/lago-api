# frozen_string_literal: true

module Integrations
  module Aggregator
    module SalesOrders
      class CreateService < Integrations::Aggregator::Invoices::BaseService
        def action_path
          "v1/#{provider}/salesorders"
        end

        def call
          return result unless integration
          return result unless integration.sync_sales_orders
          return result unless invoice.finalized?

          response = http_client.post_with_response(payload('salesorder'), headers)
          result.external_id = JSON.parse(response.body)

          IntegrationResource.create!(
            integration:,
            external_id: result.external_id,
            syncable_id: invoice.id,
            syncable_type: 'Invoice',
            resource_type: :sales_order,
          )

          result
        rescue LagoHttpClient::HttpError => e
          error = e.json_message
          code = error['type']
          message = error.dig('payload', 'message')

          deliver_error_webhook(customer:, code:, message:)

          raise e
        end
      end
    end
  end
end
