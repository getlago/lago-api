# frozen_string_literal: true

module Charges
  module ChargeModels
    class GraduatedService < Charges::ChargeModels::BaseService
      protected

      def ranges
        properties['graduated_ranges']&.map(&:with_indifferent_access)
      end

      def amount_details
        {
          graduated_ranges: ranges.each_with_object([]) do |range, amounts|
            amounts << Charges::AmountDetails::RangeGraduatedService.call(range:, total_units: units)
            break amounts if range[:to_value].nil? || range[:to_value] >= units
          end
        }
      end

      def compute_amount
        amount_details.fetch(:graduated_ranges).sum { |e| e[:total_with_flat_amount] }
      end

      def unit_amount
        total_units = aggregation_result.full_units_number || units
        return 0 if total_units.zero?

        compute_amount / total_units
      end
    end
  end
end
