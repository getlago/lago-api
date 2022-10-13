# frozen_string_literal: true

module Charges
  module ChargeModels
    class VolumeService < Charges::ChargeModels::BaseService
      protected

      def ranges
        charge.properties['volume_ranges']&.map(&:with_indifferent_access)
      end

      def compute_amount
        return 0 if units.zero?

        flat_amount = BigDecimal(matching_range[:flat_amount])
        per_unit_amount = BigDecimal(matching_range[:per_unit_amount])

        units * per_unit_amount + flat_amount
      end

      def matching_range
        @matching_range ||= ranges.find do |range|
          range[:from_value] <= units && (!range[:to_value] || units <= range[:to_value])
        end
      end
    end
  end
end
