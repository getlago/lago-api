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
          return result unless fallback_item

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
        end
      end
    end
  end
end
