# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CustomService < BillableMetrics::Aggregations::BaseService
      def compute_aggregation(options: {})
        # TODO(custom_agg): Implement custom aggregation logic
        result.aggregation = 0
        result.count = event_store.count
        result.options = options
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
    end
  end
end
