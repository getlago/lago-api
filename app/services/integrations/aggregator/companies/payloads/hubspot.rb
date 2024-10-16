# frozen_string_literal: true

module Integrations
  module Aggregator
    module Companies
      module Payloads
        class Hubspot < Integrations::Aggregator::Contacts::Payloads::BasePayload
          def create_body
            {
              'properties' => {
                'name' => customer.name,
                'domain' => customer.url,
                'lago_customer_id' => customer.id,
                'lago_customer_external_id' => customer.external_id,
                'lago_billing_email' => customer.email,
                'lago_tax_identification_number' => customer.tax_identification_number,
                'lago_customer_link' => customer_url
              }
            }
          end

          def update_body
            {
              'companyId' => integration_customer.external_customer_id,
              'input' => {
                'properties' => {
                  'name' => customer.name,
                  'domain' => customer.url,
                  'lago_customer_id' => customer.id,
                  'lago_customer_external_id' => customer.external_id,
                  'lago_billing_email' => customer.email,
                  'lago_tax_identification_number' => customer.tax_identification_number,
                  'lago_customer_link' => customer_url
                }
              }
            }
          end
        end
      end
    end
  end
end
