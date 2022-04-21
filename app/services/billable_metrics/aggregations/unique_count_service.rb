# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:)
        result.aggregation = events_scope(from_date: from_date, to_date: to_date)
          .count(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              [
                'DISTINCT (events.properties->>?)',
                billable_metric.field_name,
              ],
            ),
          )
        result
      end
    end
  end
end
