# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class TradeTransaction < Builder
        def call(&block)
          xml.comment "Supply Chain Trade Transaction"
          xml["rsm"].SupplyChainTradeTransaction do
            yield xml
          end
        end
      end
    end
  end
end
