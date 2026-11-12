# frozen_string_literal: true

module Events
  module Stores
    # Answers from the pre-aggregated usage buckets the aggregations they cover, and delegates the
    # rest to the store it wraps.
    class UsageBucketStore < SimpleDelegator
      # A snapshot this close before the window is the one of the subscription's previous period:
      # its `to_datetime` is the last microsecond of that period.
      ADJACENT_SNAPSHOT_GAP = 1.second

      # `recurring` charges sum every period since the subscription started: the buckets only answer
      # the window opening at `charges_from_datetime`, on top of the snapshot of the period before it.
      def initialize(store, usage_buckets:, charge_id:, charge_filter_id:, recurring: false, charges_from_datetime: nil)
        @usage_buckets = usage_buckets
        @charge_id = charge_id
        @charge_filter_id = charge_filter_id
        @recurring = recurring
        @charges_from_datetime = charges_from_datetime

        super(store)
      end

      def precomputed?
        true
      end

      def count
        aggregation_result
      end

      # Without a snapshot, the window alone would be served as the recurring total.
      def sum(with_count: true)
        return super if recurring

        aggregation_result
      end

      def sum_precise_total_amount_cents
        return super if recurring

        usage_buckets.precise_total_amount_cents_for(charge_id:, charge_filter_id:)
      end

      # Current usage persists no snapshot, so the result carries no snapshot units.
      def recurring_sum(watermark:, period: nil)
        return super if recurring_fallback_reason(period)

        BaseStore::RecurringAggregationResult.new(
          value: aggregation_result.value,
          snapshot_value: 0,
          events_count: aggregation_result.events_count,
          snapshot_events_count: 0
        )
      end

      def grouped_recurring_sum(watermark:, period: nil)
        return super if recurring_fallback_reason(period)

        grouped_aggregation_results.map do |result|
          BaseStore::GroupedRecurringAggregationResult.new(
            groups: result.groups,
            value: result.value,
            snapshot_value: 0,
            events_count: result.events_count,
            snapshot_events_count: 0
          )
        end
      end

      # Why the delta from `period` must come from the events: a late ingestion is an event the
      # snapshot missed. Snapshots the buckets can never complete are refused by the Provider.
      # The events tell it, not the buckets: their ingestion time is not the one the watermark bounds.
      def recurring_fallback_reason(period)
        return "no_period" if period.nil?
        return "not_adjacent" unless adjacent?(period)

        "late_ingestion" if late_ingestion?(period)
      end

      # Asked again by the recurring reads of the same period
      def late_ingestion?(period)
        @late_ingestion ||= {}
        @late_ingestion.fetch(period) { @late_ingestion[period] = super }
      end

      def max(with_count: true)
        aggregation_result
      end

      # The events store counts every event of the window here (`count() OVER ()`), not the single
      # event it returns the value of, which is what the summed bucket counts amount to.
      def last(with_count: true)
        aggregation_result
      end

      # A non-default `columns` is the presentation breakdown, which the Provider refuses, so the
      # delegation below is a guard rather than a path.
      def grouped_count(columns = nil)
        return super if columns

        grouped_aggregation_results
      end

      def grouped_sum(columns = nil, with_count: true)
        return super if columns
        # Without columns, so the wrapped store groups on its own keys rather than on nil.
        return __getobj__.grouped_sum(with_count:) if recurring

        grouped_aggregation_results
      end

      def grouped_sum_precise_total_amount_cents
        return super if recurring

        usage_buckets.grouped_precise_total_amount_cents_for(charge_id:, charge_filter_id:)
      end

      def grouped_max(columns = nil, with_count: true)
        return super if columns

        grouped_aggregation_results
      end

      def grouped_last(columns = nil, with_count: true)
        return super if columns

        grouped_aggregation_results
      end

      private

      attr_reader :usage_buckets, :charge_id, :charge_filter_id, :recurring, :charges_from_datetime

      def adjacent?(period)
        gap = charges_from_datetime - period.to_datetime

        gap.positive? && gap <= ADJACENT_SNAPSHOT_GAP
      end

      def aggregation_result
        usage_buckets.aggregation_result_for(charge_id:, charge_filter_id:)
      end

      def grouped_aggregation_results
        usage_buckets.grouped_aggregation_results_for(charge_id:, charge_filter_id:)
      end
    end
  end
end
