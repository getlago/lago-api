# frozen_string_literal: true

module Charges
  module ChargeModels
    class VolumeService < Charges::ChargeModels::BaseService
      protected

      def ranges
        properties['volume_ranges']&.map(&:with_indifferent_access)
      end

      def compute_amount
        return 0 if units.zero?

        flat_amount = BigDecimal(matching_range[:flat_amount])
        per_unit_amount = BigDecimal(matching_range[:per_unit_amount])

        units * per_unit_amount + flat_amount
      end

      def matching_range
        number_of_units = (charge.prorated? && result.full_units_number) ? result.full_units_number : units

        @matching_range ||= ranges.find do |range|
          range[:from_value] <= number_of_units && (!range[:to_value] || number_of_units <= range[:to_value])
        end
      end
    end
  end
end
