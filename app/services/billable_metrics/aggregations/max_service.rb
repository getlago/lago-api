# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class MaxService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        events = fetch_events(from_datetime:, to_datetime:)

        result.aggregation = events.maximum("(#{sanitized_field_name})::numeric") || 0
        result.count = events.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      def compute_per_event_aggregation
        events = fetch_events(from_datetime:, to_datetime:)

        max_value = events.maximum("(#{sanitized_field_name})::numeric") || 0
        event_values = events.pluck(Arel.sql("(#{sanitized_field_name})::numeric"))
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

      private

      def fetch_events(from_datetime:, to_datetime:)
        events_scope(from_datetime:, to_datetime:)
          .where(field_presence_condition)
          .where(field_numeric_condition)
      end
    end
  end
end
