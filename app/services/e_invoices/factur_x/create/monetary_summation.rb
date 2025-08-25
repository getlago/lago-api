# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class MonetarySummation < Builder
        def call
          xml.comment "Monetary Summation"
          xml["ram"].SpecifiedTradeSettlementHeaderMonetarySummation do
            xml["ram"].LineTotalAmount format_number(invoice.fees_amount)
            xml["ram"].ChargeTotalAmount format_number(0)
            xml["ram"].AllowanceTotalAmount format_number(invoice.coupons_amount)
            xml["ram"].TaxBasisTotalAmount format_number(invoice.sub_total_excluding_taxes_amount)
            xml["ram"].TaxTotalAmount format_number(invoice.taxes_amount), currencyID: invoice.currency
            xml["ram"].GrandTotalAmount format_number(invoice.sub_total_including_taxes_amount)
            xml["ram"].TotalPrepaidAmount format_number(total_prepaid_amount)
            xml["ram"].DuePayableAmount format_number(due_payable_amount)
          end
        end
      end
    end
  end
end
