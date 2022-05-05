# frozen_string_literal: true

module Charges
  class GraduatedRangesService < BaseService
    def initialize(ranges:)
      @ranges = ranges.map(&:with_indifferent_access)

      super(nil)
    end

    def validate
      errors = []

      if ranges.blank?
        errors << :missing_graduated_range
        return errors
      end

      next_from_value = 0
      ranges.each_with_index do |range, index|
        errors << :invalid_graduated_amount unless valid_amounts?(range)
        errors << :invalid_graduated_currency unless valid_currencies?(range)
        errors << :invalid_graduated_ranges unless valid_bounds?(range, index, next_from_value)

        next_from_value = (range[:to_value] || 0) + 1
      end

      return result.fail!(:invalid_ranges, errors) if errors.present?

      result
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

    def valid_bounds?(range, index, next_from_value)
      range[:from_value] == (next_from_value) && (
        index == (ranges.size - 1) && range[:to_value].nil? ||
        index < (ranges.size - 1) && (range[:to_value] || 0) > range[:from_value]
      )
    end

    def currencies
      Currencies::ACCEPTED_CURRENCIES.keys.map(&:to_s).map(&:upcase)
    end
  end
end
