# frozen_string_literal: true

module EInvoices
  module FacturX
    class LineItem < BaseService
      def initialize(xml:, resource:, fee:, line_id:)
        super(xml:, resource:)

        @fee = fee
        @line_id = line_id
      end

      def call
        xml.comment "Line Item #{line_id}: #{line_item_description}"
        xml["ram"].IncludedSupplyChainTradeLineItem do
          xml["ram"].AssociatedDocumentLineDocument do
            xml["ram"].LineID line_id
          end
          xml["ram"].SpecifiedTradeProduct do
            xml["ram"].Name fee.item_name
            xml["ram"].Description fee.description.presence || line_item_description
          end
          xml["ram"].SpecifiedLineTradeAgreement do
            xml["ram"].NetPriceProductTradePrice do
              xml["ram"].ChargeAmount fee.precise_unit_amount
            end
          end
          xml["ram"].SpecifiedLineTradeDelivery do
            xml["ram"].BilledQuantity billed_quantity, unitCode: UNIT_CODE
          end
          xml["ram"].SpecifiedLineTradeSettlement do
            xml["ram"].ApplicableTradeTax do
              xml["ram"].TypeCode VAT
              xml["ram"].CategoryCode category_code
              xml["ram"].RateApplicablePercent fee.taxes_rate unless outside_scope_of_tax?
            end
            xml["ram"].SpecifiedTradeSettlementLineMonetarySummation do
              xml["ram"].LineTotalAmount format_number(line_total_amount)
            end
          end
        end
      end

      private

      attr_accessor :line_id, :fee

      def credit_note?
        resource.is_a?(CreditNote)
      end

      def billed_quantity
        credit_note? ? -fee.units : fee.units
      end

      def line_total_amount
        credit_note? ? -fee.amount : fee.amount
      end

      def category_code
        @_category_code ||= tax_category_code(type: fee.fee_type, tax_rate: fee.taxes_rate)
      end

      def outside_scope_of_tax?
        category_code == O_CATEGORY
      end

      def line_item_description
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
