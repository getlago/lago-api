# frozen_string_literal: true

module FixedCharges
  module FixedChargesEvents
    class AggregationService < BaseAggregationService
      Result = BaseResult[
        :aggregation, # Total units from events
        :current_usage_units, # Units for current usage
        :full_units_number, # Total units ignoring proration
        :count, # Number of events
        :total_aggregated_units # Total aggregated units
      ]

      def call
        result.aggregation = fixed_charge_events.last.units
        result.current_usage_units = result.aggregation
        result.full_units_number = result.aggregation
        result.count = events.count
        result.total_aggregated_units = result.aggregation

        result
      end
    end
  end
end
