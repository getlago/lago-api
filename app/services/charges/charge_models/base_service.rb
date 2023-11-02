# frozen_string_literal: true

module Charges
  module ChargeModels
    class BaseService < ::BaseService
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

        if aggregation_result.total_aggregated_units
          result.total_aggregated_units = aggregation_result.total_aggregated_units
        end

        result
      end

      protected

      attr_accessor :charge, :aggregation_result, :properties

      delegate :units, to: :result

      def compute_amount
        raise NotImplementedError
      end

      def unit_amount
        # TODO: Uncomment this.
        # raise NotImplementedError
        0
      end
    end
  end
end
