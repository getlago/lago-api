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

    # Visit only the tiers reached by this segment. Earlier units select the starting
    # tier; they neither contribute to its variable amount nor trigger earlier flat fees.
    def priced_ranges(segment_units)
      tiers = ranges
      half_open = half_open_ranges?(tiers)
      carried = carryover_units
      closing_units = carried + BigDecimal(segment_units.to_s)
      tiers.each_with_object([]) do |range, details|
        upper = range[:to_value] && BigDecimal(range[:to_value].to_s)
        next if carried.positive? && upper && upper <= carried

        lower = BigDecimal(range.fetch(:from_value).to_s)
        lower -= 1 unless half_open || lower.zero? # Legacy tiers start at the previous upper bound + 1.
        lower = [lower, carried].max if carried.positive?
        range_end = (upper && upper < closing_units) ? upper : closing_units
        details << yield(range, range_end - lower)
        break details if !upper || closing_units <= upper
      end
    end

    def half_open_ranges?(tiers)
      AdjacentRanges.adjacent?(tiers)
    end
  end
end
