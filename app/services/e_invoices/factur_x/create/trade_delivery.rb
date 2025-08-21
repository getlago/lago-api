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
                xml["udt"].DateTimeString formatted_date(oldest_charges_from_datetime), format: CCYYMMDD
              end
            end
          end
        end
      end
    end
  end
end
