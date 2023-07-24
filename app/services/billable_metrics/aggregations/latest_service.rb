module BillableMetrics
  module Aggregations
    class LatestService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_datetime:, to_datetime:, options: {})
        events = events_scope(from_datetime:, to_datetime:)
          .where("#{sanitized_field_name} IS NOT NULL").order(timestamp: :desc)

        if events.count == 0
          result.aggregation = 0
          result.count = 0
          result.options = options

        latest_event = events.first

        result.aggregation = latest_event&.properties&.fetch(billable_metric.field_name, 0)
        result.count = events.count || 0
        result.options = options

        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end
    end
  end
end
