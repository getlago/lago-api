# frozen_string_literal: true

module Charges
  module ChargeModels
    class BaseService < ::BaseService
      Result = BaseResult[
        :units, # Result of the aggregation
        :current_usage_units, # Number of units for current usage (manly used for prorated or in advance charges)
        :full_units_number, # Total number of aggregated units ingoring proration
        :count, # Total number of events used for the aggregation
        :amount, # Amount result of the charge model applied on the units
        :unit_amount, # Amount per unit
        :amount_details, # Details of the amount calculation. Depends on the charge model.
        :total_aggregated_units, # Total number of aggregated units in the case of a weighted sum aggregation
        :grouped_by, # Groups applied on event properties for the aggregation
        :grouped_results # Array containing the result for compatibility with grouped aggregation
      ]

      def self.apply(...)
        new(...).apply
      end

      def initialize(charge:, aggregation_result:, properties:)
        super(nil)
        @charge = charge
        @aggregation_result = aggregation_result
        @properties = properties
      end

      def apply
        result.units = aggregation_result.aggregation
        result.current_usage_units = aggregation_result.current_usage_units
        result.full_units_number = aggregation_result.full_units_number
        result.count = aggregation_result.count
        result.amount = compute_amount
        result.unit_amount = unit_amount
        result.amount_details = amount_details

        if aggregation_result.total_aggregated_units
          result.total_aggregated_units = aggregation_result.total_aggregated_units
        end

        result.grouped_results = [result]
        result
      end

      protected

      attr_accessor :charge, :aggregation_result, :properties

      delegate :units, to: :result
      delegate :grouped_by, to: :aggregation_result

      def compute_amount
        raise NotImplementedError
      end

      def unit_amount
        raise NotImplementedError
      end

      def amount_details
        {}
      end
    end
  end
end
