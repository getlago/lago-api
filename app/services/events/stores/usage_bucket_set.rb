# frozen_string_literal: true

module Events
  module Stores
    # Pre-aggregated usage for one subscription over one window, indexed by charge and
    # charge filter. Immutable; build one per computation.
    class UsageBucketSet
      Totals = Data.define(:units, :events_count)

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

      # The pipeline values a count metric's events at 1 apiece, so units is the
      # aggregation for both count and sum. A missing row means no usage, hence zero.
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
