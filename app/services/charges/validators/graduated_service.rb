# frozen_string_literal: true

module Charges
  module Validators
    class GraduatedService < Charges::Validators::BaseService
      def validate
        errors = []

        if ranges.blank?
          errors << :missing_graduated_range
          return result.fail!(:invalid_properties, errors)
        end

        next_from_value = 0
        ranges.each_with_index do |range, index|
          errors << :invalid_amount unless valid_amounts?(range)
          errors << :invalid_graduated_ranges unless valid_bounds?(range, index, next_from_value)

          next_from_value = (range[:to_value] || 0) + 1
        end

        return result.fail!(:invalid_properties, errors) if errors.present?

        result
      end

      private

      def ranges
        charge.properties.map(&:with_indifferent_access)
      end

      def valid_amounts?(range)
        # NOTE: as we want to be the more precise with decimals, we only
        # accept amount that are in string to avoid float bad parsing
        # and use BigDecimal as a source of truth when computing amounts
        return false unless range[:per_unit_amount].is_a?(String)
        return false unless range[:flat_amount].is_a?(String)

        per_unit_amount = BigDecimal(range[:per_unit_amount])
        flat_amount = BigDecimal(range[:flat_amount])

        per_unit_amount.finite? &&
          flat_amount.finite? &&
          (per_unit_amount.zero? || per_unit_amount.positive?) &&
          (flat_amount.zero? || flat_amount.positive?)
      # NOTE: If BigDecimal can't parse the amount, it will trigger
      # an ArgumentError is the type is not a numeric, ei: 'foo'
      # a TypeError is the amount is nil
      rescue ArgumentError, TypeError
        false
      end

      def valid_bounds?(range, index, next_from_value)
        range[:from_value] == (next_from_value) && (
          index == (ranges.size - 1) && range[:to_value].nil? ||
          index < (ranges.size - 1) && (range[:to_value] || 0) > range[:from_value]
        )
      end
    end
  end
end
