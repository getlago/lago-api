# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeAllowanceCharge < Builder
        INVOICE_DISCOUNT = false
        INVOICE_ADDITIONAL_CHARGE = true

        def initialize(xml:, invoice:, tax_rate:, amount:)
          @tax_rate = tax_rate
          @amount = amount
          super(xml:, invoice:)
        end

        def call
          xml.comment "Allowance/Charge - Discount #{percent(tax_rate)} portion"
          xml["ram"].SpecifiedTradeAllowanceCharge do
            xml["ram"].ChargeIndicator do
              xml["udt"].Indicator INVOICE_DISCOUNT
            end
            xml["ram"].ActualAmount format_number(amount)
            xml["ram"].Reason reason
            xml["ram"].CategoryTradeTax do
              xml["ram"].TypeCode VAT
              xml["ram"].CategoryCode category_code(tax_rate:)
              xml["ram"].RateApplicablePercent format_number(tax_rate)
            end
          end
        end

        private

        attr_accessor :tax_rate, :amount

        def reason
          I18n.t("invoice.e_invoicing.discount_reason", tax_rate: percent(tax_rate))
        end
      end
    end
  end
end
