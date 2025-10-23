# frozen_string_literal: true

module EInvoices
  module FacturX
    class CrossIndustryInvoice < BaseSerializer
      def call
        xml["rsm"].CrossIndustryInvoice(ROOT_NAMESPACES) do
          xml.comment "Exchange Document Context"
          xml["rsm"].ExchangedDocumentContext do
            xml["ram"].GuidelineSpecifiedDocumentContextParameter do
              xml["ram"].ID "urn:cen.eu:en16931:2017"
            end
          end

          yield
        end
      end
    end
  end
end
