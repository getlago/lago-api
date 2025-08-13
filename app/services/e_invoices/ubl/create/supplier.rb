# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class Supplier < Builder
        delegate :billing_entity, to: :invoice

        def call
          xml.comment "Supplier Party"
          xml["cac"].AccountingSupplierParty do
            xml["cac"].Party do
              xml["cac"].PostalAddress do
                xml["cbc"].StreetName billing_entity.address_line1
                xml["cbc"].CityName billing_entity.city
                xml["cbc"].PostalZone billing_entity.zipcode
                xml["cbc"].Country do
                  xml["cbc"].IdentificationCode billing_entity.country
                end
              end
              xml["cac"].PartyTaxScheme do
                xml["cbc"].CompanyID billing_entity.tax_identification_number
                xml["cbc"].TaxScheme do
                  xml["cbc"].ID VAT
                end
              end
              xml["cac"].PartyLegalEntity do
                xml["cbc"].RegistrationName billing_entity.legal_name
              end
            end
          end
        end
      end
    end
  end
end
