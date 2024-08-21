# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      module Payloads
        class Netsuite < BasePayload
          def create_body
            {
              'type' => 'customer', # Fixed value
              'isDynamic' => false, # Fixed value
              'columns' => {
                'companyname' => customer.name,
                'subsidiary' => subsidiary_id,
                'custentity_lago_id' => customer.id,
                'custentity_lago_sf_id' => customer.external_salesforce_id,
                'custentity_form_activeprospect_customer' => customer.name, # TODO: Will be removed
                'custentity_lago_customer_link' => customer_url,
                'email' => customer.email,
                'phone' => customer.phone
              },
              'options' => {
                'ignoreMandatoryFields' => false # Fixed value
              }
            }
          end

          def update_body
            {
              'type' => 'customer',
              'recordId' => integration_customer.external_customer_id,
              'values' => {
                'companyname' => customer.name,
                'subsidiary' => integration_customer.subsidiary_id,
                'custentity_lago_sf_id' => customer.external_salesforce_id,
                'custentity_form_activeprospect_customer' => customer.name, # TODO: Will be removed
                'custentity_lago_customer_link' => customer_url,
                'email' => customer.email,
                'phone' => customer.phone
              },
              'options' => {
                'isDynamic' => false
              }
            }
          end

          private

          def customer_url
            url = ENV["LAGO_FRONT_URL"].presence || "https://app.getlago.com"

            URI.join(url, "/customer/", customer.id).to_s
          end
        end
      end
    end
  end
end
