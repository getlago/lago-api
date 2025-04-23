# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      module Payloads
        class Avalara < BasePayload
          def create_body
            [
              {
                "company_id" => integration.company_id&.to_i,
                "external_id" => customer.id,
                "name" => name,
                "address_line_1" => customer.shipping_address_line1 || customer.address_line1,
                "city" => customer.shipping_city || customer.city,
                "zip" => customer.shipping_zipcode || customer.zipcode,
                "country" => customer.shipping_country || customer.country,
                "state" => customer.shipping_state || customer.state,
                "tax_number" => customer.tax_identification_number
              }
            ]
          end

          def update_body
            [
              {
                "company_id" => integration.company_id&.to_i,
                "external_id" => customer.id,
                "name" => name,
                "address_line_1" => customer.shipping_address_line1 || customer.address_line1,
                "city" => customer.shipping_city || customer.city,
                "zip" => customer.shipping_zipcode || customer.zipcode,
                "country" => customer.shipping_country || customer.country,
                "state" => customer.shipping_state || customer.state,
                "tax_number" => customer.tax_identification_number
              }
            ]
          end

          private

          def name
            return customer.name if customer.name.present?

            "#{customer.firstname} #{customer.lastname}".strip
          end
        end
      end
    end
  end
end
