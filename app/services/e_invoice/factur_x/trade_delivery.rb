# frozen_string_literal: true

module EInvoice
  module FacturX
    class TradeDelivery
      def initialize(xml)
        @xml = xml
      end

      def call()
        xml.comment "Applicable Header Trade Delivery"
        xml["ram"].ApplicableHeaderTradeDelivery do
          xml["ram"].ActualDeliverySupplyChainEvent do
            xml["ram"].OccurrenceDateTime do
              xml["udt"].DateTimeString '20250527', format: 102
            end
          end
        end
      end
 
      private

      attr_accessor :xml, :invoice
    end
  end
end
