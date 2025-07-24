# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class TradeDelivery < Builder
        def call
          xml.comment "Applicable Header Trade Delivery"
          xml["ram"].ApplicableHeaderTradeDelivery do
            xml["ram"].ActualDeliverySupplyChainEvent do
              xml["ram"].OccurrenceDateTime do
                xml["udt"].DateTimeString '20250527', format: 102
              end
            end
          end
        end
      end
    end
  end
end
