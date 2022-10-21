# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class MaxService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        events = events_scope(from_date: from_date, to_date: to_date)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.maximum("(#{sanitized_field_name})::numeric") || 0
        result.aggregation_per_group = aggregation_per_group(events, aggregation_select)
        result.count = events.count
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      private

      def aggregation_select
        "max((#{sanitized_field_name})::numeric)"
      end
    end
  end
end
