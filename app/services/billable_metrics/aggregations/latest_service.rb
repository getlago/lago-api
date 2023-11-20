# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class LatestService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def aggregate(options: {})
        result.aggregation = compute_aggregation(event_store.last)
        result.count = event_store.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      private

      def compute_aggregation(latest_event)
        result = if latest_event.present?
          value = latest_event.properties.fetch(billable_metric.field_name, 0).to_s
          BigDecimal(value).negative? ? 0 : value
        else
          0
        end

        BigDecimal(result)
      end
    end
  end
end
