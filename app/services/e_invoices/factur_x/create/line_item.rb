# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class LineItem < Builder
        def initialize(xml:, line_id:, fee:)
          super(xml:)
          @line_id = line_id
          @fee = fee
        end

        def call
          xml.comment "Line Item #{line_id}: #{item_description}"
          xml["ram"].IncludedSupplyChainTradeLineItem do
            xml["ram"].AssociatedDocumentLineDocument do
              xml["ram"].LineID line_id
            end
            xml["ram"].SpecifiedTradeProduct do
              xml["ram"].Name fee.item_name
              xml["ram"].Description fee.description.presence || item_description
            end
            xml["ram"].SpecifiedLineTradeAgreement do
              xml["ram"].NetPriceProductTradePrice do
                xml["ram"].ChargeAmount fee.precise_unit_amount
              end
            end
            xml["ram"].SpecifiedLineTradeDelivery do
              xml["ram"].BilledQuantity fee.units, unitCode: UNIT_CODE
            end
            xml["ram"].SpecifiedLineTradeSettlement do
              xml["ram"].ApplicableTradeTax do
                xml["ram"].TypeCode VAT
                xml["ram"].CategoryCode tax_category(fee.taxes_rate)
                xml["ram"].RateApplicablePercent fee.taxes_rate
              end
              xml["ram"].SpecifiedTradeSettlementLineMonetarySummation do
                xml["ram"].LineTotalAmount format_number(fee.amount)
              end
            end
          end
        end

        private

        attr_accessor :line_id, :fee

        def item_description
          return fee.invoice_name if fee.invoice_name.present?

          I18n.t(
            "invoice.subscription_interval",
            plan_interval: I18n.t("invoice.#{fee.subscription.plan.interval}"),
            plan_name: fee.subscription.plan.invoice_name
          )
        end
      end
    end
  end
end
