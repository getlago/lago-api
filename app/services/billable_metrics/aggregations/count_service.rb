# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CountService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        result.aggregation = event_store.count
        result.current_usage_units = result.aggregation
        result.count = result.aggregation
        result.pay_in_advance_aggregation = BigDecimal(1)
        result.options = { running_total: running_total(options) }
        result
      end

      # NOTE: Return cumulative sum of event count based on the number of free units
      #       (per_events or per_total_aggregation).
      def running_total(options)
        free_units_per_events = options[:free_units_per_events].to_i
        free_units_per_total_aggregation = BigDecimal(options[:free_units_per_total_aggregation] || 0)

        return [] if free_units_per_events.zero? && free_units_per_total_aggregation.zero?

        (1..result.aggregation).to_a
      end

      def compute_per_event_aggregation
        (0...event_store.count).map { |_| 1 }
      end
    end
  end
end
