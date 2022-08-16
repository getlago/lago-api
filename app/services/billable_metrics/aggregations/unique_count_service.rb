# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, free_units_count: 0)
         events = events_scope(from_date: from_date, to_date: to_date)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.count("DISTINCT (#{sanitized_field_name})")
        result.count = events.count
        result
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
    end
  end
end
