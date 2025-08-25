# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class ApplicableTradeTax < Builder
        def initialize(xml:, invoice:, tax_rate:, amount:, tax:)
          @tax_rate = tax_rate
          @amount = amount
          @tax = tax

          super(xml:, invoice:)
        end

        def call
          xml.comment "Tax Information #{percent(tax_rate)} #{VAT}"
          xml["ram"].ApplicableTradeTax do
            xml["ram"].CalculatedAmount format_number(tax)
            xml["ram"].TypeCode VAT
            xml["ram"].BasisAmount format_number(amount)
            tax_category_code = tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)
            xml["ram"].CategoryCode tax_category_code
            if tax_category_code == O_CATEGORY
              xml["ram"].ExemptionReasonCode O_VAT_EXEMPTION
            else
              xml["ram"].RateApplicablePercent format_number(tax_rate)
            end
          end
        end

        private

        attr_accessor :tax_rate, :amount, :tax
      end
    end
  end
end
