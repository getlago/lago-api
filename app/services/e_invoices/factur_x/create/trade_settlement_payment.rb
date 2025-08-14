# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeSettlementPayment < Builder
        def initialize(xml:, invoice:, type:, amount: nil)
          @type = type
          @amount = amount
          super(xml:, invoice:)
        end

        def call
          xml.comment "Payment Means: #{payment_label}"
          xml["ram"].SpecifiedTradeSettlementPaymentMeans do
            xml["ram"].TypeCode type
            xml["ram"].Information payment_information
          end
        end

        private

        attr_accessor :type, :amount
      end
    end
  end
end
