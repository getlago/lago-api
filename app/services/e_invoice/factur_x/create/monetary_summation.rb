# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class MonetarySummation < Builder
        def call
          xml.comment "Monetary Summation"
          xml["ram"].SpecifiedTradeSettlementHeaderMonetarySummation do
            xml["ram"].LineTotalAmount format_number(1000)
            xml["ram"].ChargeTotalAmount format_number(0.0)
            xml["ram"].AllowanceTotalAmount format_number(10.0)
            xml["ram"].TaxBasisTotalAmount format_number(990.00)
            xml["ram"].TaxTotalAmount format_number(198.84), currencyID: invoice.currency
            xml["ram"].GrandTotalAmount format_number(1188.84)
            xml["ram"].TotalPrepaidAmount format_number(21.86)
            xml["ram"].DuePayableAmount format_number(1166.98)
          end
        end
      end
    end
  end
end
