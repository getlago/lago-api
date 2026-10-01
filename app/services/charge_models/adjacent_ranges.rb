# frozen_string_literal: true

module ChargeModels
  # Ranges are adjacent when each starts where the previous one ends; units are
  # then counted half-open instead of with a one-unit step between tiers.
  module AdjacentRanges
    def self.adjacent?(ranges)
      ranges.present? && ranges.size >= 2 && ranges.each_cons(2).all? do |prev, curr|
        BigDecimal(curr[:from_value].to_s) == BigDecimal((prev[:to_value] || 0).to_s)
      end
    end

    private

    def adjacent_ranges?
      return @adjacent_ranges if defined?(@adjacent_ranges)

      @adjacent_ranges = AdjacentRanges.adjacent?(ranges)
    end
  end
end
