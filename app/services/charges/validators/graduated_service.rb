# frozen_string_literal: true

module Charges
  module Validators
    class GraduatedService < Charges::Validators::BaseService
      def validate
        errors = []

        if ranges.blank?
          errors << :missing_graduated_range
          return result.fail!(code: :invalid_properties, message: errors)
        end

        next_from_value = 0
        ranges.each_with_index do |range, index|
          errors << :invalid_amount unless valid_amounts?(range)
          errors << :invalid_graduated_ranges unless valid_bounds?(range, index, next_from_value)

          next_from_value = (range[:to_value] || 0) + 1
        end

        return result.fail!(code: :invalid_properties, message: errors) if errors.present?

        result
      end

      private

      def ranges
        charge.properties.map(&:with_indifferent_access)
      end

      def valid_amounts?(range)
        ::Validators::DecimalAmountService.new(range[:per_unit_amount]).valid_amount? &&
          ::Validators::DecimalAmountService.new(range[:flat_amount]).valid_amount?
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
