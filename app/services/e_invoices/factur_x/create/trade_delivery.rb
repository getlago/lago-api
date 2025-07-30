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

        private

        def oldest_charges_from_datetime
          return invoice.created_at if invoice.one_off?

          invoice.subscriptions.map do |subscription|
            ::Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)
              .charges_from_datetime
          end.min
        end
      end
    end
  end
end
