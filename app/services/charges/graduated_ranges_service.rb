# frozen_string_literal: true

module Charges
  class GraduatedRangesService
    def initialize(ranges)
      @ranges = ranges.with_indifferent_access
      @errors = []
    end

    def validate
      if ranges.blank?
        errors << :missing_graduated_range
        return errors
      end

      last_to_value = nil
      ranges.each_with_index do |range, index|
        errors << :invalid_graduated_amount unless valid_amounts?(range)
        errors << :invalid_graduated_currency unless valid_currencies?(range)
        errors << :invalid_graduated_ranges unless valid_bounds?(range, index, last_to_value || 0)

        last_to_value = range[:to_value]
      end

      errors.uniq
    end

    private

    attr_reader :ranges, :errors

    def valid_amounts?(range)
      range[:per_unit_price_amount_cents].is_a?(Numeric) &&
        range[:flat_amount_cents].is_a?(Numeric) &&
        !range[:per_unit_price_amount_cents].negative? &&
        !range[:flat_amount_cents].negative?
    end

    def valid_currencies?(range)
      currencies.include?(range[:per_unit_price_amount_currency]) &&
        currencies.include?(range[:flat_amount_currency])
    end

    def valid_bounds?(range, index, last_to_value)
      range[:from_value] == (last_to_value + 1) && (
        index == (ranges.size - 1) && range[:to_value].nil? ||
        index < (ranges.size - 1) && (range[:to_value] || 0) > range[:from_value]
      )
    end

    def currencies
      ACCEPTED_CURRENCIES.keys.map(&:to_s).map(&:upcase)
    end
  end
end
