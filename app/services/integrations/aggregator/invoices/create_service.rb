# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class CreateService < BaseService
        def action_path
          "v1/#{provider}/invoices"
        end

        def call
          return unless integration
          return unless integration.sync_invoices
          return unless invoice.finalized?
          return unless fallback_item

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
        end
      end
    end
  end
end
