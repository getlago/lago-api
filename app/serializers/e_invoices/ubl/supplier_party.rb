# frozen_string_literal: true

module EInvoices
  module Ubl
    class SupplierParty < BaseSerializer
      Options = Data.define(:tax_registration) do
        def initialize(tax_registration: true)
          super
        end
      end

      delegate :billing_entity, to: :resource

      def initialize(xml:, resource:, options: Options.new)
        super(xml:, resource:)

        @options = options
      end

      def call
        xml.comment "Supplier Party"
        xml["cac"].AccountingSupplierParty do
          xml["cac"].Party do
            xml["cac"].PostalAddress do
              xml["cbc"].StreetName billing_entity.address_line1
              xml["cbc"].AdditionalStreetName billing_entity.address_line2
              xml["cbc"].CityName billing_entity.city
              xml["cbc"].PostalZone billing_entity.zipcode
              xml["cac"].Country do
                xml["cbc"].IdentificationCode billing_entity.country
              end
            end
            if render_tax_registration?
              xml["cac"].PartyTaxScheme do
                xml["cbc"].CompanyID billing_entity.tax_identification_number
                xml["cac"].TaxScheme do
                  xml["cbc"].ID VAT
                end
              end
            end
            xml["cac"].PartyLegalEntity do
              xml["cbc"].RegistrationName billing_entity.legal_name
              xml["cbc"].CompanyID billing_entity.tax_identification_number
            end
          end
        end
      end

      private

      attr_accessor :options

      def render_tax_registration?
        options && !!options.tax_registration
      end
    end
  end
end
