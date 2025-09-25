# frozen_string_literal: true

module EInvoices
  module FacturX
    class TradeSettlement < BaseService
      def call
        xml.comment "Applicable Header Trade Settlement"
        xml["ram"].ApplicableHeaderTradeSettlement do
          xml["ram"].InvoiceCurrencyCode resource.currency
          yield
        end
      end
    end
  end
end
