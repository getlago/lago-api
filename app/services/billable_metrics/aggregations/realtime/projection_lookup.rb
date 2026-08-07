# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    module Realtime
      # Shared lookup for the realtime aggregators: fetches the projection row
      # matching the aggregation scope and verifies its billing period agrees
      # with the boundaries computed by Subscriptions::DatesService. Any
      # disagreement or missing row returns nil, which makes the aggregator
      # fall back to the events-store path.
      module ProjectionLookup
        BOUNDARY_TOLERANCE = 1.second

        private

        def projection_row
          return @projection_row if defined?(@projection_row)

          row = UsageRealtimeProjection.covering(Time.current).find_by(
            subscription_id: subscription.id,
            charge_id: charge.id,
            charge_filter_id: charge_filter&.id.to_s,
            grouped_by: "{}"
          )

          row = nil if row && !boundaries_agree?(row)
          @projection_row = row
        end

        def boundaries_agree?(row)
          charges_from = boundaries.respond_to?(:charges_from_datetime) ? boundaries.charges_from_datetime : boundaries[:charges_from_datetime]
          return false if charges_from.nil?

          (row.period_charges_from - charges_from).abs <= BOUNDARY_TOLERANCE
        end
      end
    end
  end
end
