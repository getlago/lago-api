# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      module Payloads
        class Netsuite < BasePayload
          def create_body
            {
              'type' => 'customer', # Fixed value
              'isDynamic' => true, # Fixed value
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
              },
              'lines' => lines
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

          def lines
            if customer.same_billing_and_shipping_address?
              [
                {
                  'lineItems' => [
                    {
                      'defaultshipping' => true,
                      'defaultbilling' => true,
                      'subObjectId' => 'addressbookaddress',
                      'subObject' => {
                        'addr1' => customer.address_line1,
                        'addr2' => customer.address_line2,
                        'city' => customer.city,
                        'zip' => customer.zipcode,
                        'state' => customer.state,
                        'country' => customer.country
                      }
                    }
                  ],
                  'sublistId' => 'addressbook'
                }
              ]
            else
              [
                {
                  'lineItems' => [
                    {
                      'defaultshipping' => false,
                      'defaultbilling' => true,
                      'subObjectId' => 'addressbookaddress',
                      'subObject' => {
                        'addr1' => customer.address_line1,
                        'addr2' => customer.address_line2,
                        'city' => customer.city,
                        'zip' => customer.zipcode,
                        'state' => customer.state,
                        'country' => customer.country
                      }
                    },
                    {
                      'defaultshipping' => true,
                      'defaultbilling' => false,
                      'subObjectId' => 'addressbookaddress',
                      'subObject' => {
                        'addr1' => customer.shipping_address_line1,
                        'addr2' => customer.shipping_address_line2,
                        'city' => customer.shipping_city,
                        'zip' => customer.shipping_zipcode,
                        'state' => customer.shipping_state,
                        'country' => customer.shipping_country
                      }
                    }
                  ],
                  'sublistId' => 'addressbook'
                }
              ]
            end
          end

          def customer_url
            url = ENV["LAGO_FRONT_URL"].presence || "https://app.getlago.com"

            URI.join(url, "/customer/", customer.id).to_s
          end
        end
      end
    end
  end
end
