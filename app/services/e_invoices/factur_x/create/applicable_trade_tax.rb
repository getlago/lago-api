# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class ApplicableTradeTax < Builder
        def initialize(xml:, invoice:, applied_tax:)
          @applied_tax = applied_tax
          super(xml:, invoice:)
        end

        def call
          xml.comment "Tax Information #{percent(applied_tax.tax_rate)} #{VAT}"
          xml["ram"].ApplicableTradeTax do
            xml["ram"].CalculatedAmount format_number(applied_tax.amount)
            xml["ram"].TypeCode VAT
            xml["ram"].BasisAmount format_number(applied_tax.fees_amount)
            applied_tax_category_code = category_code(type: invoice.invoice_type, tax_rate: applied_tax.tax_rate)
            xml["ram"].CategoryCode applied_tax_category_code
            if applied_tax_category_code == O_CATEGORY
              xml["ram"].ExemptionReasonCode O_VAT_EXEMPTION
            else
              xml["ram"].RateApplicablePercent format_number(applied_tax.tax_rate)
            end
          end
        end

        private

        attr_accessor :applied_tax
      end
    end
  end
end
