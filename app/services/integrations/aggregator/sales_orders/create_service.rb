# frozen_string_literal: true

module Integrations
  module Aggregator
    module SalesOrders
      class CreateService < Integrations::Aggregator::Invoices::BaseService
        def action_path
          "v1/#{provider}/salesorders"
        end

        def call
          return unless integration
          return unless integration.sync_sales_orders
          return unless invoice.finalized?
          return unless fallback_item

          response = http_client.post_with_response(payload('salesorder'), headers)
          result.external_id = JSON.parse(response.body)

          IntegrationResource.create!(
            integration:,
            external_id: result.external_id,
            syncable_id: invoice.id,
            syncable_type: 'SalesOrder',
          )

          result
        end
      end
    end
  end
end
