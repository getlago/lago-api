# frozen_string_literal: true

module Events
  module Stores
    # Pre-aggregated usage for one subscription over one window, indexed by charge and
    # charge filter. Immutable; build one per computation.
    class UsageBucketSet
      # `last_event_at` orders the latest fold, which a `skip_grouping` read runs across groups.
      # `precise_total_amount_cents` is only written on sum rows, and zero on every other type.
      Totals = Data.define(:aggregation_type, :units, :events_count, :last_event_at, :precise_total_amount_cents) do
        def initialize(precise_total_amount_cents: BigDecimal(0), **)
          super
        end

        # The buckets are keyed by charge, so two rows of one key always share their type.
        def combine(other)
          with(
            units: combined_units(other),
            events_count: events_count + other.events_count,
            precise_total_amount_cents: precise_total_amount_cents + other.precise_total_amount_cents,
            last_event_at: [last_event_at, other.last_event_at].max
          )
        end

        private

        def combined_units(other)
          case aggregation_type
          when "max_agg" then [units, other.units].max
          when "latest_agg" then (other.last_event_at > last_event_at) ? other.units : units
          else units + other.units
          end
        end
      end

      # Copied before freezing: the caller usually builds these hashes as accumulators, and
      # freezing its own object would raise on the next write, far from here.
      def initialize(totals: {}, grouped_totals: {})
        @totals = totals.dup.freeze
        @grouped_totals = grouped_totals.dup.freeze
        freeze
      end

      def empty?
        totals.empty? && grouped_totals.empty?
      end

      # The charge filters the buckets hold usage for, the empty string being the default bucket
      # the stream writes where the events store has no filter.
      def charge_filter_ids_for(charge_id:)
        totals.keys.filter_map { |(id, charge_filter_id)| charge_filter_id if id == charge_id }
      end

      def aggregation_result_for(charge_id:, charge_filter_id:)
        bucket_totals = totals_for(charge_id:, charge_filter_id:)

        BaseStore::AggregationResult.new(
          value: bucket_totals&.units || BigDecimal(0),
          events_count: bucket_totals&.events_count || 0
        )
      end

      def grouped_aggregation_results_for(charge_id:, charge_filter_id:)
        grouped_totals_for(charge_id:, charge_filter_id:).map do |groups, bucket_totals|
          BaseStore::GroupedAggregationResult.new(
            groups:,
            value: bucket_totals.units,
            events_count: bucket_totals.events_count
          )
        end
      end

      def precise_total_amount_cents_for(charge_id:, charge_filter_id:)
        totals_for(charge_id:, charge_filter_id:)&.precise_total_amount_cents || BigDecimal(0)
      end

      # Hashes rather than a result object: the shape the events store returns for this read.
      def grouped_precise_total_amount_cents_for(charge_id:, charge_filter_id:)
        grouped_totals_for(charge_id:, charge_filter_id:).map do |groups, bucket_totals|
          {groups:, value: bucket_totals.precise_total_amount_cents}
        end
      end

      private

      attr_reader :totals, :grouped_totals

      def totals_for(charge_id:, charge_filter_id:)
        totals[[charge_id, charge_filter_id]]
      end

      def grouped_totals_for(charge_id:, charge_filter_id:)
        grouped_totals[[charge_id, charge_filter_id]] || []
      end
    end
  end
end
