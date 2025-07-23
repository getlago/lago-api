# frozen_string_literal: true

module EInvoice
  module FacturX
    class TradeTransaction
      def initialize(xml, invoice:)
        @xml = xml
        @invoice = invoice
      end

      def call(&block)
        xml.comment "Supply Chain Trade Transaction"
        xml['rsm'].SupplyChainTradeTransaction do
          yield xml
        end
      end
 
      private

      attr_accessor :xml, :invoice
    end
  end
end
