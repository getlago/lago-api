# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class TaxSubtotal < Builder
        def initialize(xml:, invoice:, tax_rate:, amount:, tax:)
          @tax_rate = tax_rate
          @amount = amount
          @tax = tax

          super(xml:, invoice:)
        end

        def call
          xml.comment "Tax Information #{percent(tax_rate)} #{VAT}"
          xml["cac"].TaxSubtotal do
            xml["cbc"].TaxableAmount format_number(amount), currencyID: invoice.currency
            xml["cbc"].TaxAmount format_number(tax), currencyID: invoice.currency
            applied_tax_category_code = tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)
            xml["cac"].TaxCategory do
              xml["cbc"].ID applied_tax_category_code
              if applied_tax_category_code == O_CATEGORY
                xml["cbc"].TaxExemptionReasonCode O_VAT_EXEMPTION
                xml["cbc"].TaxExemptionReason "Not subject to VAT"
              else
                xml["cbc"].Percent format_number(tax_rate)
              end
              xml["cac"].TaxScheme do
                xml["cbc"].ID VAT
              end
            end
          end
        end

        private

        attr_accessor :tax_rate, :amount, :tax
      end
    end
  end
end
