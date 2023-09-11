# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        # TODO
        result.aggregation = 0
        result.current_usage_units = 0
        result.count = 0
        result.pay_in_advance_aggregation = BigDecimal(0)
        result.options = { running_total: 0 }
        result
      end
    end
  end
end
