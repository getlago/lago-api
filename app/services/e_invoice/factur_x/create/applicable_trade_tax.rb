# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class ApplicableTradeTax < Builder
        def initialize(xml:, invoice:, tax:)
          @tax = tax
          super(xml:, invoice:)
        end

        def call
          xml.comment "Tax Information #{percent(tax.rate)} VAT"
          xml["ram"].ApplicableTradeTax do
            xml["ram"].CalculatedAmount format_number(tax.amount * tax.rate)
            xml["ram"].TypeCode VAT
            xml["ram"].BasisAmount format_number(tax.amount)
            xml["ram"].CategoryCode S_CATEGORY
            xml["ram"].RateApplicablePercent format_number(tax.rate * 100)
          end
        end

        private

        attr_accessor :tax
      end
    end
  end
end
