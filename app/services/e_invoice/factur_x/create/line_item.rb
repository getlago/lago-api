# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class LineItem < Builder
        def initialize(xml:, line_id:, fee:)
          super(xml:)
          @line_id = line_id
          @fee = fee
        end

        def call
          xml.comment "Line Item #{line_id}: #{fee.invoice_name}"
          xml["ram"].IncludedSupplyChainTradeLineItem do
            xml["ram"].AssociatedDocumentLineDocument do
              xml["ram"].LineID line_id
            end
            xml["ram"].SpecifiedTradeProduct do
              xml["ram"].Name fee.item_name
              xml["ram"].Description fee.invoice_name
            end
            xml["ram"].SpecifiedLineTradeAgreement do
              xml["ram"].NetPriceProductTradePrice do
                xml["ram"].ChargeAmount fee.amount
              end
            end
            xml["ram"].SpecifiedLineTradeDelivery do
              xml["ram"].BilledQuantity fee.units, unitCode: "C62"
            end
            xml["ram"].SpecifiedLineTradeSettlement do
              xml["ram"].ApplicableTradeTax do
                xml["ram"].TypeCode VAT
                xml["ram"].CategoryCode S_CATEGORY
                xml["ram"].RateApplicablePercent fee.taxes_rate
              end
              xml["ram"].SpecifiedTradeSettlementLineMonetarySummation do
                xml["ram"].LineTotalAmount fee.total_amount
              end
            end
          end
        end

        private

        attr_accessor :line_id, :fee
      end
    end
  end
end
