# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CustomService < BillableMetrics::Aggregations::BaseService
      def compute_aggregation(options: {})
        # TODO(custom_agg): Implement custom aggregation logic
        result.aggregation = 0
        result.count = event_store.count
        result.options = options
        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result
      end

      def compute_grouped_by_aggregation
        # TODO(custom_agg): Implement custom aggregation logic
        result.aggregations = []
      end

      def compute_per_event_aggregation
        # TODO(custom_agg): Implement custom aggregation logic
        []
      end

      def compute_pay_in_advance_aggregation
        return BigDecimal(0) unless event

        cached_aggregation = find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: grouped_by_values,
        )

        unless cached_aggregation
          # TODO(custom_agg): Implement custom aggregation logic
        end

        # TODO(custom_agg): Implement custom aggregation logic
        BigDecimal(0)
      end
    end
  end
end
