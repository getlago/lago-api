# frozen_string_literal: true

module EInvoices
  module Ubl
    class CustomerParty < BaseSerializer
      delegate :customer, to: :resource

      def serialize
        xml.comment "Customer Party"
        xml["cac"].AccountingCustomerParty do
          xml["cac"].Party do
            xml["cac"].PostalAddress do
              xml["cbc"].StreetName customer.address_line1
              xml["cbc"].AdditionalStreetName customer.address_line2
              xml["cbc"].CityName customer.city
              xml["cbc"].PostalZone customer.zipcode
              xml["cac"].Country do
                xml["cbc"].IdentificationCode customer.country
              end
            end
            xml["cac"].PartyLegalEntity do
              xml["cbc"].RegistrationName customer.name
            end
          end
        end
      end
    end
  end
end
