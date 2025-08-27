# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class ApplicableTradeTax < Builder
        def initialize(xml:, invoice:, tax_rate:, amount:, tax:)
          super(xml:, invoice:)

          @tax_rate = tax_rate
          @amount = amount
          @tax = tax
        end

        def call
          xml.comment "Tax Information #{percent(tax_rate)} #{VAT}"
          xml["ram"].ApplicableTradeTax do
            xml["ram"].CalculatedAmount format_number(tax)
            xml["ram"].TypeCode VAT
            xml["ram"].BasisAmount format_number(amount)
            xml["ram"].CategoryCode category_code
            if outside_scope_of_tax?
              xml["ram"].ExemptionReasonCode O_VAT_EXEMPTION
            else
              xml["ram"].RateApplicablePercent format_number(tax_rate)
            end
          end
        end

        private

        attr_accessor :tax_rate, :amount, :tax

        def category_code
          @_category_code ||= tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)
        end

        def outside_scope_of_tax?
          category_code == O_CATEGORY
        end
      end
    end
  end
end
