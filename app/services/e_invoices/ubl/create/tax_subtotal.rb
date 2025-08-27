# frozen_string_literal: true

module EInvoices
  module Ubl
    module Create
      class TaxSubtotal < Builder
        def initialize(xml:, invoice:, tax_rate:, amount:, tax:)
          super(xml:, invoice:)

          @tax_rate = tax_rate
          @amount = amount
          @tax = tax
        end

        def call
          xml.comment "Tax Information #{percent(tax_rate)} #{VAT}"
          xml["cac"].TaxSubtotal do
            xml["cbc"].TaxableAmount format_number(taxable_amount), currencyID: invoice.currency
            xml["cbc"].TaxAmount format_number(tax), currencyID: invoice.currency
            xml["cac"].TaxCategory do
              xml["cbc"].ID applied_tax_category_code
              if outside_scope_of_tax?
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

        def applied_tax_category_code
          @_applied_tax_category_code ||= tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)
        end

        def taxable_amount
          return 0 if tax_rate.zero?

          amount
        end

        def outside_scope_of_tax?
          applied_tax_category_code == O_CATEGORY
        end
      end
    end
  end
end
