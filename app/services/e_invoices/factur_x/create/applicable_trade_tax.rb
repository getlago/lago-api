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
            xml["ram"].CategoryCode S_CATEGORY
            xml["ram"].RateApplicablePercent format_number(applied_tax.tax_rate)
          end
        end

        private

        attr_accessor :applied_tax
      end
    end
  end
end
