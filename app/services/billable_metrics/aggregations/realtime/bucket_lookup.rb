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
      # The window start is floored to its bucket wall, see
      # RealtimeUsage.bucket_floor.
      #
      # PREFETCH: Fees::ChargeService builds one aggregator per charge filter plus one for the
      # default bucket, so querying here once per aggregator is an N+1 over a window that
      # Events::BillingPeriodFilterService has already read in full. When it hands its rows down
      # (`prefetched_buckets`, see BaseService#initialize) they are used instead of querying.
      #
      # A prefetch of {} is NOT the same as no prefetch: it means the batch read found no buckets
      # for this charge filter, which has to produce the same nil/[] answer a query would have, so
      # the aggregator falls back to the events store. nil means no batch ran and we query.
      module BucketLookup
        BucketTotals = Struct.new(:units, :events_count)

        # grouped_by value the pipeline writes for a charge with no pricing group keys.
        UNGROUPED = "{}"

        private

        def bucket_totals
          return @bucket_totals if defined?(@bucket_totals)

          @bucket_totals = nil

          count, events_count, units = if prefetched_buckets
            # nil when this charge filter is absent from the batch read, which destructures to
            # three nils and lands on the no-buckets branch below.
            prefetched_buckets[UNGROUPED]
          elsif bucket_window_from
            bucket_scope
              .where(grouped_by: UNGROUPED)
              .pick(Arel.sql("count(), sum(events_count), sum(units)"))
          end

          if count.nil? || count.zero?
            nil
          else
            @bucket_totals = BucketTotals.new(BigDecimal(units.to_s), events_count)
          end
        end

        # Per-group totals for the aggregation scope, with the grouped_by
        # JSON parsed back into a hash. Returns [] (=> caller falls back to
        # the events store) when there are no rows or when any row's group
        # keys differ from the charge's current pricing_group_keys (stale
        # attribution after a charge edit).
        def grouped_bucket_totals
          return @grouped_bucket_totals if defined?(@grouped_bucket_totals)

          @grouped_bucket_totals = []

          rows = if prefetched_buckets
            prefetched_buckets
              .reject { |grouped_by_json, _totals| grouped_by_json == UNGROUPED }
              .map { |grouped_by_json, (_count, events_count, units)| [grouped_by_json, events_count, units] }
          elsif bucket_window_from
            bucket_scope
              .where.not(grouped_by: UNGROUPED)
              .group(:grouped_by)
              .pluck(Arel.sql("grouped_by, sum(events_count), sum(units)"))
          else
            []
          end

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

          @bucket_window_from = RealtimeUsage.bucket_floor(from)
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
