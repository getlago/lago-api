# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class SimpleAggregationService < BaseService
      def call
        events_in_range.last.try(:units) || 0
      end
    end
  end
end
