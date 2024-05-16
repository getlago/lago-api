# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class UpdateService < BaseService
        def initialize(integration:, integration_customer:)
          @integration_customer = integration_customer

          super(integration:)
        end

        def call
          response = http_client.put_with_response(params, headers)

          deliver_success_webhook(customer:)

          result.contact_id = JSON.parse(response.body)
          result
        rescue LagoHttpClient::HttpError => e
          error = e.json_message
          code = error['type']
          message = error.dig('payload', 'message')

          deliver_error_webhook(customer:, code:, message:)

          result.service_failure!(code:, message:)
        end

        private

        attr_reader :integration_customer, :subsidiary_id

        delegate :customer, to: :integration_customer

        def params
          {
            'type' => 'customer',
            'recordId' => integration_customer.external_customer_id,
            'values' => {
              'companyname' => customer.name,
              'subsidiary' => integration_customer.subsidiary_id,
              'custentity_lago_sf_id' => customer.external_salesforce_id,
              'custentity_form_activeprospect_customer' => customer.name, # TODO: Will be removed
              'email' => customer.email,
              'phone' => customer.phone,
            },
            'options' => {
              'isDynamic' => false,
            },
          }
        end
      end
    end
  end
end
