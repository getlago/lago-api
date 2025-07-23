# frozen_string_literal: true

module EInvoice
  module FacturX
    class LineItem
      def initialize(xml)
        @xml = xml
      end

      def call(attrs:)
        xml.comment "Line Item #{attrs[:line_id]}: #{attrs[:description]}"
        xml['ram'].IncludedSupplyChainTradeLineItem do
          xml['ram'].AssociatedDocumentLineDocument do
            xml['ram'].LineID attrs[:line_id]
          end
          xml['ram'].SpecifiedTradeProduct do
            xml['ram'].Name attrs[:name]
            xml['ram'].Description attrs[:description]
          end
          xml['ram'].SpecifiedLineTradeAgreement do
            xml['ram'].NetPriceProductTradePrice do
              xml['ram'].ChargeAmount attrs[:charge_amount]
            end
          end
          xml['ram'].SpecifiedLineTradeDelivery do
            xml['ram'].BilledQuantity attrs[:billed_quantity], unitCode: "C62"
          end
          xml['ram'].SpecifiedLineTradeSettlement do
            xml['ram'].ApplicableTradeTax do
              xml['ram'].TypeCode "VAT"
              xml['ram'].CategoryCode "S"
              xml['ram'].RateApplicablePercent attrs[:rate_applicable_percent]
            end
            xml['ram'].SpecifiedTradeSettlementLineMonetarySummation do
              xml['ram'].LineTotalAmount attrs[:line_total_amount]
            end
          end
        end
      end
 
      private

      attr_accessor :xml, :invoice
    end
  end
end
