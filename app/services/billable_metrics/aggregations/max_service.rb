# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class MaxService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_datetime:, to_datetime:, options: {})
        events = events_scope(from_datetime: from_datetime, to_datetime: to_datetime)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.maximum("(#{sanitized_field_name})::numeric") || 0
        result.count = events.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end
    end
  end
end
