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
      properties = rate_properties.to_h.deep_stringify_keys

      RANGE_KEYS.each do |key|
        ranges = properties[key]
        next unless ranges.is_a?(Array) && ranges.any?

        if ranges.any? { !it.is_a?(Hash) || it.key?("from_value") }
          return result.single_validation_failure!(field: key.to_sym, error_code: "from_value_not_allowed")
        end

        bounds = upper_bounds(ranges)
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
    # last tier is open-ended. Checked on the stored values: a decimal finer than a
    # float keeps would otherwise pass here and collapse onto its neighbour.
    def upper_bounds(ranges)
      *closed, last = ranges.map { it["to_value"] }
      return unless last.nil?

      bounds = closed.map { stored_bound(it) }
      return if bounds.any? { it.nil? || !it.positive? }
      return unless bounds.each_cons(2).all? { |low, high| high > low }

      bounds + [nil]
    end

    def stored_bound(value)
      return if value.nil? || value.is_a?(TrueClass) || value.is_a?(FalseClass)

      bound = BigDecimal(value.to_s)
      return unless bound.finite?

      bound.frac.zero? ? bound.to_i : bound.to_f
    rescue ArgumentError
      nil
    end
  end
end
