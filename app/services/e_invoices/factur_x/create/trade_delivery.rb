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
                xml["udt"].DateTimeString formatted_date(oldest_subscription_start_date), format: YYMMDD
              end
            end
          end
        end

        private

        def oldest_subscription_start_date
          # TODO Confirm with Raffi if this is correct!!
          invoice.subscriptions.order(subscriptions: {started_at: :asc}).first.started_at
        end
      end
    end
  end
end
