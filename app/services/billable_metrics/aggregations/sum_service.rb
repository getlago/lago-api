# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class SumService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:)
        result.aggregation = events_scope(from_date: from_date, to_date: to_date)
          .where("#{sanitized_field_name} IS NOT NULL")
          .sum("(#{sanitized_field_name})::numeric")

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
    end
  end
end
