# frozen_string_literal: true

module Charges
  module ChargeModels
    class GraduatedService < Charges::ChargeModels::BaseService
      protected

      def ranges
        charge.properties.map(&:with_indifferent_access)
      end

      def compute_amount
        ranges.reduce(0) do |result_amount, range|
          flat_amount = BigDecimal(range[:flat_amount])
          per_unit_amount = BigDecimal(range[:per_unit_amount])

          # NOTE: Add flat amount to the total
          result_amount += flat_amount unless value.zero?

          units = compute_range_units(range[:from_value], range[:to_value])
          result_amount += units * per_unit_amount

          # NOTE: aggregation_result.aggregation is between the bounds of the current range,
          #       we must stop the loop
          break result_amount if range[:to_value].nil? || range[:to_value] >= value

          result_amount
        end
      end

      # NOTE: compute how many units to bill in the range
      def compute_range_units(from_value, to_value)
        # NOTE: value is higher than the to_value of the range
        if to_value && value >= to_value
          return to_value - (from_value.zero? ? 1 : from_value) + 1
        end

        return to_value - from_value if to_value && value >= to_value
        return value if from_value.zero?

        # NOTE: value is in the range
        value - from_value + 1
      end

      def value
        aggregation_result.aggregation
      end
    end
  end
end
