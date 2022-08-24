# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class SumService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, free_units_count: 0)
        events = events_scope(from_date: from_date, to_date: to_date)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.sum("(#{sanitized_field_name})::numeric")
        result.count = events.count
        result.options = { running_total: running_total(events, free_units_count) }
        result
      rescue ActiveRecord::StatementInvalid => e
        result.fail!(code: 'aggregation_failure', message: e.message)
      end

      private

      def sanitized_field_name
        ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            'events.properties->>?',
            billable_metric.field_name,
          ],
        )
      end

      # NOTES: Return cumulative sum of field_name based on the number of free units.
      def running_total(events, free_units_count)
        total = 0.0
        events = events.order(created_at: :asc)
        events = events.limit(free_units_count) unless free_units_count.zero?

        events.pluck(Arel.sql("(#{sanitized_field_name})::numeric"))
          .map { |x| total += x }
      end
    end
  end
end
