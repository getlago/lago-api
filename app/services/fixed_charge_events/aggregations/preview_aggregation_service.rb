# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class PreviewAggregationService < BaseService
      def call
        result.aggregation = fixed_charge.units
        result.full_units_number = fixed_charge.units
        result
      end
    end
  end
end
