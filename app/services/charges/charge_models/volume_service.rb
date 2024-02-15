# frozen_string_literal: true

module Charges
  module ChargeModels
    class VolumeService < Charges::ChargeModels::BaseService
      protected

      def ranges
        properties['volume_ranges']&.map(&:with_indifferent_access)&.sort_by { |h| h[:from_value] }
      end

      def compute_amount
        return 0 if units.zero?

        per_unit_total_amount + flat_unit_amount
      end

      def unit_amount
        return 0 if number_of_units.zero?

        compute_amount / number_of_units
      end

      def amount_details
        if number_of_units.zero?
          return {
            flat_unit_amount: BigDecimal(0),
            per_unit_amount: BigDecimal(0),
            per_unit_total_amount: BigDecimal(0),
          }
        end

        {
          flat_unit_amount:,
          per_unit_amount: per_unit_amount.to_s,
          per_unit_total_amount:,
        }
      end

      def flat_unit_amount
        @flat_unit_amount ||= BigDecimal(matching_range[:flat_amount])
      end

      def per_unit_amount
        @per_unit_amount ||= per_unit_total_amount.fdiv(number_of_units)
      end

      def per_unit_total_amount
        @per_unit_total_amount ||= units * BigDecimal(matching_range[:per_unit_amount])
      end

      def matching_range
        @matching_range ||= ranges.each_with_index do |range, index|
          is_matching = if index.zero?
            range[:from_value] <= number_of_units && (!range[:to_value] || number_of_units <= range[:to_value])
          else
            (range[:from_value] - 1) < number_of_units && (!range[:to_value] || number_of_units <= range[:to_value])
          end

          return range if is_matching
        end

        nil
      end

      def number_of_units
        @number_of_units ||= (charge.prorated? && result.full_units_number) ? result.full_units_number : units
      end
    end
  end
end
