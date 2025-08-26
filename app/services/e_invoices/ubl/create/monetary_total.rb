# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class MonetaryTotal < Builder
        def call
          xml.comment "Legal Monetary Total"
          xml["cac"].LegalMonetaryTotal do
            xml["cbc"].LineExtensionAmount format_number(invoice.fees_amount), currencyID: invoice.currency
            xml["cbc"].TaxExclusiveAmount format_number(invoice.sub_total_excluding_taxes_amount), currencyID: invoice.currency
            xml["cbc"].TaxInclusiveAmount format_number(invoice.sub_total_including_taxes_amount), currencyID: invoice.currency
            xml["cbc"].AllowanceTotalAmount format_number(Money.new(allowances)), currencyID: invoice.currency
            xml["cbc"].ChargeTotalAmount format_number(0), currencyID: invoice.currency
            xml["cbc"].PrepaidAmount format_number(total_prepaid_amount), currencyID: invoice.currency
            xml["cbc"].PayableAmount format_number(due_payable_amount), currencyID: invoice.currency
          end
        end
      end
    end
  end
end
