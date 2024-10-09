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
                'isperson' => isperson,
                'subsidiary' => subsidiary_id,
                'custentity_lago_id' => customer.id,
                'custentity_lago_sf_id' => customer.external_salesforce_id,
                'custentity_lago_customer_link' => customer_url,
                'email' => email,
                'phone' => phone
              }.merge(names),
              'options' => {
                'ignoreMandatoryFields' => false # Fixed value
              }
            }.merge(include_lines? ? {'lines' => lines} : {})
          end

          def update_body
            {
              'type' => 'customer',
              'recordId' => integration_customer.external_customer_id,
              'values' => {
                'isperson' => isperson,
                'subsidiary' => integration_customer.subsidiary_id,
                'custentity_lago_sf_id' => customer.external_salesforce_id,
                'custentity_lago_customer_link' => customer_url,
                'email' => email,
                'phone' => phone
              }.merge(names),
              'options' => {
                'isDynamic' => false
              }
            }
          end

          private

          def names
            # customer_type might be nil -> in that case it's a company so we better check for an individual type here
            return {'companyname' => customer.name} unless customer.customer_type_individual?

            names_hash = {'firstname' => customer.firstname, 'lastname' => customer.lastname}

            customer.name.present? ? names_hash.merge('companyname' => customer.name) : names_hash
          end

          def isperson
            customer.customer_type_individual? ? 'T' : 'F'
          end

          def include_lines?
            !integration.legacy_script && !customer.empty_billing_and_shipping_address?
          end

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
        end
      end
    end
  end
end
