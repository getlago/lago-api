# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      class CreateService < BaseService
        def initialize(integration:, customer:, subsidiary_id:)
          @customer = customer
          @subsidiary_id = subsidiary_id

          super(integration:)
        end

        def call
          response = http_client.post_with_response(params, headers)

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

        attr_reader :customer, :subsidiary_id

        def params
          {
            'type' => 'customer', # Fixed value
            'isDynamic' => false, # Fixed value
            'columns' => {
              'companyname' => customer.name,
              'subsidiary' => subsidiary_id,
              'custentity_lago_id' => customer.id,
              'custentity_lago_sf_id' => customer.external_salesforce_id,
              'custentity_form_activeprospect_customer' => customer.name, # TODO: Will be removed
              'email' => customer.email,
              'phone' => customer.phone
            },
            'options' => {
              'ignoreMandatoryFields' => false # Fixed value
            }
          }
        end
      end
    end
  end
end
