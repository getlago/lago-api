# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class LineItem < Builder
        def initialize(xml:, line_id:, fee:)
          super(xml:)
          @line_id = line_id
          @fee = fee
        end

        def call
          xml.comment "Line Item #{line_id}: #{line_item_description}"
          xml["ram"].IncludedSupplyChainTradeLineItem do
            xml["ram"].AssociatedDocumentLineDocument do
              xml["ram"].LineID line_id
            end
            xml["ram"].SpecifiedTradeProduct do
              xml["ram"].Name fee.item_name
              xml["ram"].Description fee.description.presence || line_item_description
            end
            xml["ram"].SpecifiedLineTradeAgreement do
              xml["ram"].NetPriceProductTradePrice do
                xml["ram"].ChargeAmount fee.precise_unit_amount
              end
            end
            xml["ram"].SpecifiedLineTradeDelivery do
              xml["ram"].BilledQuantity fee.units, unitCode: UNIT_CODE
            end
            xml["ram"].SpecifiedLineTradeSettlement do
              xml["ram"].ApplicableTradeTax do
                xml["ram"].TypeCode VAT
                fee_category_code = tax_category_code(type: fee.fee_type, tax_rate: fee.taxes_rate)
                xml["ram"].CategoryCode fee_category_code
                unless fee_category_code == O_CATEGORY
                  xml["ram"].RateApplicablePercent fee.taxes_rate
                end
              end
              xml["ram"].SpecifiedTradeSettlementLineMonetarySummation do
                xml["ram"].LineTotalAmount format_number(fee.amount)
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
