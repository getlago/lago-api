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
          charges_from = if boundaries.respond_to?(:charges_from_datetime)
            boundaries.charges_from_datetime
          else
            # Fees::ChargeService#aggregator hands aggregators a plain hash
            # whose :from_datetime already is the charges window start;
            # :charges_from_datetime only exists on other boundary shapes.
            boundaries[:charges_from_datetime] || boundaries[:from_datetime]
          end
          return false if charges_from.nil?

          (row.period_charges_from - charges_from).abs <= BOUNDARY_TOLERANCE
        end

        # All per-group rows for the aggregation scope, with the grouped_by
        # JSON parsed back into a hash. Returns [] (=> caller falls back to
        # the events store) when there are no rows, when any period
        # disagrees, or when any row's group keys differ from the charge's
        # current pricing_group_keys (stale attribution after a charge edit).
        def grouped_projection_rows
          return @grouped_projection_rows if defined?(@grouped_projection_rows)

          rows = UsageRealtimeProjection.covering(Time.current).where(
            subscription_id: subscription.id,
            charge_id: charge.id,
            charge_filter_id: charge_filter&.id.to_s
          ).where.not(grouped_by: "{}").to_a

          parsed = rows.map { |row| [row, JSON.parse(row.grouped_by)] }

          valid = rows.present? &&
            rows.all? { |row| boundaries_agree?(row) } &&
            parsed.all? { |(_, groups)| groups.keys.sort == Array(grouped_by).map(&:to_s).sort }

          @grouped_projection_rows = valid ? parsed : []
        rescue JSON::ParserError
          @grouped_projection_rows = []
        end
      end
    end
  end
end
