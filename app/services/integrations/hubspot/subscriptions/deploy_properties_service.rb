# frozen_string_literal: true

module Integrations
  module Hubspot
    module Subscriptions
      class DeployPropertiesService < Integrations::Aggregator::BaseService
        VERSION = 1

        def action_path
          "v1/hubspot/properties"
        end

        def call
          return unless integration.type == 'Integrations::HubspotIntegration'
          return result if integration.subscriptions_properties_version == VERSION
          response = nil
          ActiveRecord::Base.transaction do
            response = http_client.post_with_response(payload, headers)
            integration.subscriptions_properties_version = VERSION
            integration.save!
          end
          result.response = response
          result
        rescue LagoHttpClient::HttpError
          # code = code(e)
          # message = message(e)
          # deliver_error_webhook(customer:, code:, message:)
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
            objectType: "LagoSubscriptions",
            inputs: [
              {
                groupName: "lagosubscriptions_information",
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
