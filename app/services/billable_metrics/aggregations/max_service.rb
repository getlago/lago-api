# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class MaxService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def aggregate(options: {})
        result.aggregation = event_store.max || 0
        result.count = event_store.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      def compute_per_event_aggregation
        max_value = event_store.max || 0
        event_values = event_store.events_values
        max_value_seen = false

        # NOTE: returns the first max value, 0 for all other events
        event_values.map do |value|
          if !max_value_seen && value == max_value
            max_value_seen = true

            next value
          end

          0
        end
      end
    end
  end
end
