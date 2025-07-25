# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeSettlementPayment < Builder
        STANDARD = 1
        PREPAID = 57
        CREDIT_NOTE = 97

        def initialize(xml:, invoice:, payment:)
          @payment = payment
          super(xml:, invoice:)
        end

        def call
          xml.comment "Payment Means: #{payment_label}"
          xml["ram"].SpecifiedTradeSettlementPaymentMeans do
            xml["ram"].TypeCode payment.type
            xml["ram"].Information information
          end
        end

        private

        attr_accessor :payment

        def information
          case payment.type
          when STANDARD
            "Standard payment"
          when PREPAID, CREDIT_NOTE
            "#{payment_label} of #{invoice.currency} #{payment.amount} applied"
          end
        end

        def payment_label
          case payment.type
          when PREPAID
            "Prepaid credit"
          when CREDIT_NOTE
            "Credit note"
          end
        end
      end
    end
  end
end
