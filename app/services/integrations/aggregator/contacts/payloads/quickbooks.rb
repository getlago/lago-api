# frozen_string_literal: true

module Integrations
  module Aggregator
    module Contacts
      module Payloads
        # NOTE: Updates are sparse: a field cleared in Lago is left unchanged in QuickBooks. No CurrencyRef is
        #       sent, as the Nango create-customer action does not accept one: the customer gets the company's
        #       home currency.
        class Quickbooks < BasePayload
          # QuickBooks refuses a DisplayName with a colon, a tab or a newline.
          DISPLAY_NAME_FORBIDDEN_CHARACTERS = /[:\t\r\n]/
          DISPLAY_NAME_MAX_LENGTH = 500
          NAME_MAX_LENGTH = 100

          def create_body
            mapped_fields.merge("Notes" => "#{notes_marker} (#{customer.external_id})").compact_blank
          end

          def update_body
            mapped_fields.merge("Id" => integration_customer.external_customer_id, "sparse" => true).compact_blank
          end

          def with_unique_display_name(body)
            body.merge("DisplayName" => unique_display_name) if unique_display_name
          end

          # The external id is appended to the name, which is shortened so the suffix is always kept.
          # Nil when the name already is the external id, as the suffix would not make it unique.
          def unique_display_name
            external_id = clean_display_name(customer.external_id)
            return if display_name == external_id

            suffix = " (#{external_id})"
            "#{display_name.first(DISPLAY_NAME_MAX_LENGTH - suffix.length).strip}#{suffix}"
          end

          # Written in the Notes of a customer Lago creates, to recognize it when its name is found taken.
          def notes_marker
            "Lago customer: #{customer.id}"
          end

          private

          def mapped_fields
            {
              "DisplayName" => display_name,
              "CompanyName" => company_name&.first(NAME_MAX_LENGTH),
              "GivenName" => customer.firstname&.first(NAME_MAX_LENGTH),
              "FamilyName" => customer.lastname&.first(NAME_MAX_LENGTH),
              "PrimaryEmailAddr" => email.presence && {"Address" => email},
              "PrimaryPhone" => phone.presence && {"FreeFormNumber" => phone},
              "BillAddr" => address(billing_address),
              "ShipAddr" => address(customer.shipping_address)
            }
          end

          def display_name
            @display_name ||= clean_display_name(
              customer.name.presence || "#{customer.firstname} #{customer.lastname}".strip.presence || customer.external_id
            ).first(DISPLAY_NAME_MAX_LENGTH).strip
          end

          def clean_display_name(name)
            name.to_s.gsub(DISPLAY_NAME_FORBIDDEN_CHARACTERS, " ").squish
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
