# frozen_string_literal: true

module Integrations
  module Hubspot
    module Invoices
      class DeployPropertiesService < Integrations::Aggregator::BaseService
        VERSION = 1

        def action_path
          "v1/hubspot/properties"
        end

        def call
          return unless integration.type == 'Integrations::HubspotIntegration'
          return result if integration.invoices_properties_version == VERSION
          response = http_client.post_with_response(payload, headers)
          ActiveRecord::Base.transaction do
            integration.settings = integration.reload.settings
            integration.invoices_properties_version = VERSION
            integration.save!
          end
          result.response = response
          result
        rescue LagoHttpClient::HttpError => e
          message = message(e)
          deliver_integration_error_webhook(integration:, code: 'integration_error', message:)
          result
        end

        private

        def headers
          {
            'Provider-Config-Key' => 'hubspot',
            'Authorization' => "Bearer #{secret_key}",
            'Connection-Id' => integration.connection_id
          }
        end

        def payload
          {
            objectType: "LagoInvoices",
            inputs: [
              {
                groupName: "lagoinvoices_information",
                name: "example",
                label: "example label",
                type: "string",
                fieldType: "text"
              }
            ]
          }
        end
      end
    end
  end
end
