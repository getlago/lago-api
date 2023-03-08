# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_datetime:, to_datetime:, options: {})
        result.aggregation = events_scope(from_datetime:, to_datetime:).count
        result.count = result.aggregation
        result.instant_aggregation = BigDecimal(1)
        result.options = options
        result
      end
    end
  end
end
