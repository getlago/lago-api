# frozen_string_literal: true

module Events
  module Stores
    # Answers from the pre-aggregated usage buckets the aggregations they cover, and delegates the
    # rest to the store it wraps.
    class UsageBucketStore < SimpleDelegator
      def initialize(store, usage_buckets:, charge_id:, charge_filter_id:)
        @usage_buckets = usage_buckets
        @charge_id = charge_id
        @charge_filter_id = charge_filter_id

        super(store)
      end

      def precomputed?
        true
      end

      def count
        aggregation_result
      end

      def sum(with_count: true)
        aggregation_result
      end

      def sum_precise_total_amount_cents
        usage_buckets.precise_total_amount_cents_for(charge_id:, charge_filter_id:)
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

        grouped_aggregation_results
      end

      def grouped_sum_precise_total_amount_cents
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

      attr_reader :usage_buckets, :charge_id, :charge_filter_id

      def aggregation_result
        usage_buckets.aggregation_result_for(charge_id:, charge_filter_id:)
      end

      def grouped_aggregation_results
        usage_buckets.grouped_aggregation_results_for(charge_id:, charge_filter_id:)
      end
    end
  end
end
