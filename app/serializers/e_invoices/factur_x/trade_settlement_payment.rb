# frozen_string_literal: true

module EInvoices
  module FacturX
    class TradeSettlementPayment < BaseSerializer
      def initialize(xml:, resource:, type:, amount: nil)
        super(xml:, resource:)

        @type = type
        @amount = amount
      end

      def serialize
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
