# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    module Realtime
      # Shared lookup for the realtime aggregators: sums the RisingWave-fed
      # 15-minute usage buckets (Clickhouse::UsageBucket) over the charges
      # window computed Rails-side, so no period rows are maintained
      # anywhere. No buckets in the window returns nil/[], which makes the
      # aggregator fall back to the events-store path.
      #
      # The window start is floored to its bucket wall: period boundaries
      # land on bucket walls for every real timezone (offsets are multiples
      # of 15 minutes), so the floor is exact except for subscriptions
      # starting or terminating at a mid-bucket time, which share at most
      # 15 minutes of events with the neighbour period.
      module BucketLookup
        BucketTotals = Struct.new(:units, :events_count)

        private

        def bucket_totals
          return @bucket_totals if defined?(@bucket_totals)

          @bucket_totals = nil
          return nil if bucket_window_from.nil?

          buckets, events_count, units = bucket_scope
            .where(grouped_by: "{}")
            .pick(Arel.sql("count(), sum(events_count), sum(units)"))

          return nil if buckets.nil? || buckets.zero?

          @bucket_totals = BucketTotals.new(BigDecimal(units.to_s), events_count)
        end

        # Per-group totals for the aggregation scope, with the grouped_by
        # JSON parsed back into a hash. Returns [] (=> caller falls back to
        # the events store) when there are no rows or when any row's group
        # keys differ from the charge's current pricing_group_keys (stale
        # attribution after a charge edit).
        def grouped_bucket_totals
          return @grouped_bucket_totals if defined?(@grouped_bucket_totals)

          @grouped_bucket_totals = []
          return [] if bucket_window_from.nil?

          rows = bucket_scope
            .where.not(grouped_by: "{}")
            .group(:grouped_by)
            .pluck(Arel.sql("grouped_by, sum(events_count), sum(units)"))

          parsed = rows.map do |grouped_by_json, events_count, units|
            [BucketTotals.new(BigDecimal(units.to_s), events_count), JSON.parse(grouped_by_json)]
          end

          valid = parsed.present? &&
            parsed.all? { |(_, groups)| groups.keys.sort == Array(grouped_by).map(&:to_s).sort }

          @grouped_bucket_totals = valid ? parsed : []
        rescue JSON::ParserError
          @grouped_bucket_totals = []
        end

        def bucket_scope
          Clickhouse::UsageBucket.final.where(
            organization_id: subscription.organization_id,
            subscription_id: subscription.id,
            charge_id: charge.id,
            charge_filter_id: charge_filter&.id.to_s
          ).where("bucket >= ? AND bucket <= ?", bucket_window_from, bucket_window_to)
        end

        def bucket_window_from
          return @bucket_window_from if defined?(@bucket_window_from)

          from = if boundaries.respond_to?(:charges_from_datetime)
            boundaries.charges_from_datetime
          else
            # Fees::ChargeService#aggregator hands aggregators a plain hash
            # whose :from_datetime already is the charges window start;
            # :charges_from_datetime only exists on other boundary shapes.
            boundaries[:charges_from_datetime] || boundaries[:from_datetime]
          end

          # Time#change resets sec/usec cascadingly below :min.
          @bucket_window_from = from&.change(min: from.min - from.min % 15)
        end

        def bucket_window_to
          to = if boundaries.respond_to?(:charges_to_datetime)
            boundaries.charges_to_datetime
          else
            boundaries[:charges_to_datetime] || boundaries[:to_datetime]
          end

          to || Time.current
        end
      end
    end
  end
end
