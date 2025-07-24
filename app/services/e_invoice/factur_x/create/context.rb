# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class Context < Builder
        def call
          xml.comment "Exchange Document Context"
          xml['rsm'].ExchangedDocumentContext do
            xml['ram'].GuidelineSpecifiedDocumentContextParameter do
              xml['ram'].ID "urn:cen.eu:en16931:2017"
            end
          end
        end
      end
    end
  end
end
