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

      # The key sets the written rows carry, so a caller can tell a breakdown made under the
      # charge's current pricing group keys from one left behind by an edit.
      def grouped_by_key_sets_for(charge_id:, charge_filter_id:)
        grouped_totals_for(charge_id:, charge_filter_id:).map { |groups, _| groups.keys.sort }.uniq
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
