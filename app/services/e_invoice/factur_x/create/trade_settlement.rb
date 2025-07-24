# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class TradeSettlement < Builder
        def call
          xml.comment "Applicable Header Trade Settlement"
          xml["ram"].ApplicableHeaderTradeSettlement do
            xml["ram"].InvoiceCurrencyCode invoice.currency
            yield
          end
        end
      end
    end
  end
end
