# frozen_string_literal: true

module Integrations
  module Aggregator
    module Invoices
      class FindService < BaseService
        def action_path
          "v1/#{provider}/invoices/by-tranid"
        end

        def call
          return result unless integration
          return result unless provider == "netsuite"
          return result if integration_resource

          throttle!(:netsuite)

          external_id = http_client.get(headers:, json_body: {tranid: invoice.number})

          return result if external_id.blank?

          IntegrationResource.create!(
            organization_id: integration.organization_id,
            integration:,
            external_id:,
            syncable_id: invoice.id,
            syncable_type: "Invoice",
            resource_type: :invoice
          )

          result.external_id = external_id
          result
        rescue LagoHttpClient::HttpError => e
          raise RequestLimitError.new(e) if request_limit_error?(e)

          raise e
        end

        private

        def integration_resource
          IntegrationResource.find_by(integration:, syncable: invoice, resource_type: "invoice")
        end
      end
    end
  end
end
