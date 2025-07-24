# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class TradeAllowanceCharge < Builder
        VAT = "VAT"
        S_CATEGORY = "S"

        def initialize(xml:, invoice:, discount:)
          @discount = discount
          super(xml:, invoice:)
        end

        def call
          xml.comment "Allowance/Charge - Discount #{percent(discount.rate)} portion"
          xml["ram"].SpecifiedTradeAllowanceCharge do
            xml["ram"].ChargeIndicator do
              xml["udt"].Indicator discount.indicator
            end
            xml["ram"].ActualAmount format_number(discount.amount)
            xml["ram"].Reason discount.reason
            xml["ram"].CategoryTradeTax do
              xml["ram"].TypeCode VAT
              xml["ram"].CategoryCode S_CATEGORY
              xml["ram"].RateApplicablePercent format_number(discount.rate * 100)
            end
          end
        end

        private

        attr_accessor :discount
      end
    end
  end
end
