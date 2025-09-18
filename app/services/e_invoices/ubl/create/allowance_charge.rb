# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class AllowanceCharge < Builder
        def initialize(xml:, invoice:, tax_rate:, amount:)
          super(xml:, invoice:)

          @tax_rate = tax_rate
          @amount = amount
        end

        def call
          xml.comment "Allowances and Charges - Discount #{percent(tax_rate)} portion"
          xml["cac"].AllowanceCharge do
            xml["cbc"].ChargeIndicator INVOICE_DISCOUNT
            xml["cbc"].AllowanceChargeReason discount_reason
            xml["cbc"].Amount amount, currencyID: invoice.currency
            xml["cac"].TaxCategory do
              xml["cbc"].ID tax_category_code(tax_rate:)
              xml["cbc"].Percent format_number(tax_rate)
              xml["cac"].TaxScheme do
                xml["cbc"].ID VAT
              end
            end
          end
        end

        private

        attr_accessor :tax_rate, :amount
      end
    end
  end
end
