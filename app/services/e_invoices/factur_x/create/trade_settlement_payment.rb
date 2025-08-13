# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeSettlementPayment < Builder
        # You can see more codes UNTDID 4461 here
        # https://service.unece.org/trade/untdid/d21b/tred/tred4461.htm
        STANDARD = 1
        PREPAID = 57
        CREDIT_NOTE = 97

        def initialize(xml:, invoice:, type:, amount: nil)
          @type = type
          @amount = amount
          super(xml:, invoice:)
        end

        def call
          xml.comment "Payment Means: #{payment_label}"
          xml["ram"].SpecifiedTradeSettlementPaymentMeans do
            xml["ram"].TypeCode type
            xml["ram"].Information information
          end
        end

        private

        attr_accessor :type, :amount

        def information
          case type
          when STANDARD
            payment_label
          when PREPAID, CREDIT_NOTE
            I18n.t("invoice.e_invoicing.payment_information", payment_label:, currency: invoice.currency, amount:)
          end
        end

        def payment_label
          case type
          when STANDARD
            I18n.t("invoice.e_invoicing.standard_payment")
          when PREPAID
            I18n.t("invoice.prepaid_credits")
          when CREDIT_NOTE
            I18n.t("invoice.credit_notes")
          end
        end
      end
    end
  end
end
