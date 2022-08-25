# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        result.aggregation = events_scope(from_date: from_date, to_date: to_date).count
        result
      end
    end
  end
end
