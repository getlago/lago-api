# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeSettlementPayment < Builder
        def initialize(xml:, invoice:, type:, amount: nil)
          super(xml:, invoice:)

          @type = type
          @amount = amount
        end

        def call
          xml.comment "Payment Means: #{payment_label(type)}"
          xml["ram"].SpecifiedTradeSettlementPaymentMeans do
            xml["ram"].TypeCode type
            xml["ram"].Information payment_information(type, amount)
          end
        end

        private

        attr_accessor :type, :amount
      end
    end
  end
end
