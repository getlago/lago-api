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

      def compute_aggregation(latest_value)
        result = BigDecimal((latest_value || 0).to_s)
        return BigDecimal(0) if result.negative?

        result
      end
    end
  end
end
