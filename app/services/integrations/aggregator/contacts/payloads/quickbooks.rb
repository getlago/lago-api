# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      module Payloads
        class Quickbooks < BasePayload
          def create_body
            mapped_fields.merge("Notes" => "Lago customer: #{customer.id} (#{customer.external_id})").compact_blank
          end

          def update_body
            mapped_fields.merge("Id" => integration_customer.external_customer_id, "sparse" => true).compact_blank
          end

          def with_unique_display_name(body)
            body.merge("DisplayName" => "#{display_name} (#{customer.external_id})")
          end

          private

          def mapped_fields
            {
              "DisplayName" => display_name,
              "CompanyName" => company_name,
              "GivenName" => customer.firstname,
              "FamilyName" => customer.lastname,
              "PrimaryEmailAddr" => email.presence && {"Address" => email},
              "PrimaryPhone" => phone.presence && {"FreeFormNumber" => phone},
              "BillAddr" => address(billing_address),
              "ShipAddr" => address(customer.shipping_address)
            }
          end

          def display_name
            customer.name.presence || "#{customer.firstname} #{customer.lastname}".strip.presence || customer.external_id
          end

          def company_name
            customer.legal_name.presence || (customer.name if customer.customer_type_company?)
          end

          def billing_address
            {
              address_line1: customer.address_line1,
              address_line2: customer.address_line2,
              city: customer.city,
              state: customer.state,
              zipcode: customer.zipcode,
              country: customer.country
            }
          end

          def address(fields)
            {
              "Line1" => fields[:address_line1],
              "Line2" => fields[:address_line2],
              "City" => fields[:city],
              "CountrySubDivisionCode" => fields[:state],
              "PostalCode" => fields[:zipcode],
              "Country" => fields[:country]
            }.compact_blank
          end
        end
      end
    end
  end
end
