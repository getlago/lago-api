# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class LatestService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        latest_event = events.first

        result.aggregation = compute_aggregation(latest_event)
        result.count = events.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      private

      def events
        @events ||=
          events_scope(from_datetime:, to_datetime:)
            .where("#{sanitized_field_name} IS NOT NULL")
            .reorder(timestamp: :desc)
      end

      def compute_aggregation(latest_event)
        if latest_event.present?
          value = latest_event.properties.fetch(billable_metric.field_name, 0).to_s
          BigDecimal(value).negative? ? BigDecimal(0) : BigDecimal(value)
        else
          0
        end
      end
    end
  end
end
