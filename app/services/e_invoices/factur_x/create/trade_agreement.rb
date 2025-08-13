# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeAgreement < Builder
        TAX_SCHEMA_ID = "VA"

        delegate :billing_entity, to: :invoice
        delegate :customer, to: :invoice

        def call
          xml.comment "Applicable Header Trade Agreement"
          xml["ram"].ApplicableHeaderTradeAgreement do
            xml["ram"].SellerTradeParty do
              xml["ram"].ID billing_entity.code
              xml["ram"].Name billing_entity.legal_name
              xml["ram"].PostalTradeAddress do
                xml["ram"].PostcodeCode billing_entity.zipcode
                xml["ram"].LineOne billing_entity.address_line1
                xml["ram"].LineTwo billing_entity.address_line2
                xml["ram"].CityName billing_entity.city
                xml["ram"].CountryID billing_entity.country
              end
              unless invoice.credit?
                xml["ram"].SpecifiedTaxRegistration do
                  xml["ram"].ID billing_entity.tax_identification_number, schemeID: TAX_SCHEMA_ID
                end
              end
            end
            xml["ram"].BuyerTradeParty do
              xml["ram"].Name customer.name
              xml["ram"].PostalTradeAddress do
                xml["ram"].PostcodeCode customer.zipcode
                xml["ram"].LineOne customer.address_line1
                xml["ram"].LineTwo customer.address_line2
                xml["ram"].CityName customer.city
                xml["ram"].CountryID customer.country
              end
            end
          end
        end
      end
    end
  end
end
