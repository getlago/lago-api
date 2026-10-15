# frozen_string_literal: true

module RateProperties
  # Turns catalog tiers, which only name their upper bound, into the shared
  # charge-model ranges: each tier's from_value is the previous tier's to_value.
  class NormalizeRangesService < BaseService
    Result = BaseResult[:rate_properties]

    def initialize(rate_properties:)
      @rate_properties = rate_properties
      super
    end

    def call
      # Anything but a hash is left for the record validations to judge.
      unless rate_properties.is_a?(Hash)
        result.rate_properties = rate_properties
        return result
      end

      properties = rate_properties.to_h.deep_stringify_keys

      RANGE_KEYS.each do |key|
        ranges = properties[key]
        next unless ranges.is_a?(Array) && ranges.any?

        if ranges.any? { it.is_a?(Hash) && it.key?("from_value") }
          return result.single_validation_failure!(field: key.to_sym, error_code: "from_value_not_allowed")
        end

        bounds = ranges.all?(Hash) && upper_bounds(ranges)
        return result.single_validation_failure!(field: key.to_sym, error_code: "invalid_#{key}") unless bounds

        properties[key] = ranges.each_with_index.map do |range, index|
          range.merge("from_value" => index.zero? ? 0 : bounds[index - 1], "to_value" => bounds[index])
        end
      end

      result.rate_properties = properties
      result
    end

    private

    attr_reader :rate_properties

    # Upper bounds as stored numbers, or nil unless they rise strictly and only the
    # last tier is open-ended.
    def upper_bounds(ranges)
      *closed, last = ranges.map { it["to_value"] }
      return unless last.nil?

      bounds = closed.map { stored_bound(it) }
      return if bounds.any? { it.nil? || !it.positive? }

      if bounds.each_cons(2).all? { |low, high| high > low }
        bounds + [nil]
      end
    end

    def stored_bound(value)
      return if value.nil? || value.is_a?(TrueClass) || value.is_a?(FalseClass)

      bound = BigDecimal(value.to_s)
      return unless bound.finite?

      if bound.frac.zero?
        bound.to_i
      elsif bound.n_significant_digits <= Float::DIG
        # Decimals are stored as floats, which hold 15 significant digits
        # exactly and compare exactly against usage. A finer bound is rejected
        # rather than billed against a value the customer never set.
        bound.to_f
      end
    rescue ArgumentError
      nil
    end
  end
end
