# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class MaxService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:)
        max = events_scope(from_date: from_date, to_date: to_date)
          .maximum(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              [
                '(events.properties->>?)::integer',
                billable_metric.field_name,
              ],
            ),
          )

        result.aggregation = max || 0
        result
      rescue ActiveRecord::StatementInvalid => e
        result.fail!('aggregation_failure', e.message)
      end
    end
  end
end
