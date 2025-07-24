# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class TradeAgreement < Builder
        def call
          xml.comment "Applicable Header Trade Agreement"
          xml["ram"].ApplicableHeaderTradeAgreement do
            xml["ram"].SellerTradeParty do
              xml["ram"].ID "twilio_eu"
              xml["ram"].Name "Twilio EU"
              xml["ram"].PostalTradeAddress do
                xml["ram"].PostcodeCode 10001
                xml["ram"].LineOne "Twilio Europe"
                xml["ram"].CityName "Dublin"
                xml["ram"].CountryID "IE"
              end
              xml["ram"].SpecifiedTaxRegistration do
                xml["ram"].ID "IE123456789", schemeID: "VA"
              end
            end
            xml["ram"].BuyerTradeParty do
              xml["ram"].Name "Decathlon France"
              xml["ram"].PostalTradeAddress do
                xml["ram"].PostcodeCode 75011
                xml["ram"].LineOne "100 rue decathlon"
                xml["ram"].LineTwo "Batiment D"
                xml["ram"].CityName "Paris"
                xml["ram"].CountryID "FR"
              end
            end
          end
        end
      end
    end
  end
end
