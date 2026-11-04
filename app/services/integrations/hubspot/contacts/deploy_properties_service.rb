# frozen_string_literal: true

module Integrations
  module Hubspot
    module Contacts
      class DeployPropertiesService < Integrations::Aggregator::BaseService
        Result = BaseResult[:response]

        VERSION = 1

        def action_name
          "create-properties"
        end

        def call
          return result unless integration.type == "Integrations::HubspotIntegration"
          return result if integration.contacts_properties_version == VERSION

          throttle!(:hubspot)

          response = trigger_action(payload)
          ActiveRecord::Base.transaction do
            integration.settings = integration.reload.settings
            integration.contacts_properties_version = VERSION
            integration.save!
          end
          result.response = response
          result
        rescue LagoHttpClient::HttpError => e
          message = message(e)
          deliver_integration_error_webhook(integration:, code: "integration_error", message:)
          result
        end

        private

        def payload
          {
            objectType: "contacts",
            inputs: [
              {
                groupName: "contactinformation",
                name: "lago_customer_id",
                label: "Lago Customer Id",
                type: "string",
                fieldType: "text",
                displayOrder: -1,
                hasUniqueValue: true,
                searchableInGlobalSearch: true,
                formField: true
              },
              {
                groupName: "contactinformation",
                name: "lago_customer_external_id",
                label: "Lago Customer External Id",
                type: "string",
                fieldType: "text",
                displayOrder: -1,
                hasUniqueValue: true,
                searchableInGlobalSearch: true,
                formField: true
              },
              {
                groupName: "contactinformation",
                name: "lago_billing_email",
                label: "Lago Billing Email",
                type: "string",
                fieldType: "text",
                searchableInGlobalSearch: true,
                formField: true
              },
              {
                groupName: "contactinformation",
                name: "lago_customer_link",
                label: "Lago Customer Link",
                type: "string",
                fieldType: "text",
                searchableInGlobalSearch: true,
                formField: true
              }
            ]
          }.freeze
        end
      end
    end
  end
end
