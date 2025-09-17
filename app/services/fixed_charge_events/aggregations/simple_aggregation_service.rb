# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class SimpleAggregationService < BaseService
      def call
        result.aggregation = events_in_range.last.try(:units) || 0
        result
      end
    end
  end
end
