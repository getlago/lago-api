# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class TradeDelivery < Builder
        def call
          xml.comment "Applicable Header Trade Delivery"
          xml["ram"].ApplicableHeaderTradeDelivery do
            xml["ram"].ActualDeliverySupplyChainEvent do
              xml["ram"].OccurrenceDateTime do
                xml["udt"].DateTimeString formatted_date("20250527".to_date), format: 102
              end
            end
          end
        end
      end
    end
  end
end
