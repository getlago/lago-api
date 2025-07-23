# frozen_string_literal: true

module EInvoice
  module FacturX
    class ContextBuilder
      def initialize(xml)
        @xml = xml
      end

      def call
        xml.comment "Exchange Document Context"
        xml['rsm'].ExchangedDocumentContext do
          xml['ram'].GuidelineSpecifiedDocumentContextParameter do
            xml['ram'].ID "urn:cen.eu:en16931:2017"
          end
        end
      end
 
      private

      attr_accessor :xml
    end
  end
end
