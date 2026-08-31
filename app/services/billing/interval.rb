# frozen_string_literal: true

module Billing
  # How long one billing cycle lasts: `count` calendar units of `unit`.
  class Interval < Data.define(:count, :unit)
    UNITS = %i[day week month year].freeze

    # The cadence a rate is billed on, with an override taking precedence. The override's
    # two columns are independently nullable, so each falls back to the rate on its own.
    # Reads nothing but those two attributes, so anything carrying them will do.
    def self.from(rate, override: nil)
      new(
        count: override&.billing_interval_count || rate.billing_interval_count,
        unit: override&.billing_interval_unit || rate.billing_interval_unit
      )
    end

    def initialize(count:, unit:)
      unit = unit.to_sym
      count = count.to_i

      raise ArgumentError, "Unknown interval unit: #{unit.inspect}" unless UNITS.include?(unit)
      raise ArgumentError, "Interval count must be positive, got #{count.inspect}" unless count.positive?

      super
    end

    # `time` moved by `steps` whole intervals.
    # @example: from Jan 31, advance(1) is Feb 28 and advance(2) is Mar 31
    def advance(time, steps)
      units = count * steps

      case unit
      when :day then time + units.days
      when :week then time + units.weeks
      when :month then time + units.months
      when :year then time + units.years
      end
    end

    # How many whole intervals fit between `from` and `to`. Negative when `to`
    # precedes `from`.
    #
    # @example monthly from 2022-01-31
    #   boundaries: 2021-12-31 | 2022-01-31 | 2022-02-28 | 2022-03-31
    #   2022-01-30  ->  -1   before the anchor
    #   2022-02-15  ->   0   inside [Jan 31, Feb 28)
    #   2022-02-27  ->   0   still inside, one day short of closing
    #   2022-02-28  ->   1   turns on the boundary, which opens the next interval
    def steps_between(from, to)
      estimate = calendar_steps_between(from, to)

      if advance(from, estimate) > to
        estimate - 1
      else
        estimate
      end
    end

    private

    # A bracket for steps_between: it narrows the answer to two candidates, and
    # steps_between asks `advance` which of the two is right.
    #
    # Computing the exact answer here instead would mean re-deriving where a
    # boundary lands, month-end clamping included — which is what `advance` already does
    def calendar_steps_between(from, to)
      whole_units = case unit
      when :day then (to.to_date - from.to_date).to_i
      when :week then (to.to_date - from.to_date).to_i / 7
      when :month then ((to.year - from.year) * 12) + (to.month - from.month)
      when :year then to.year - from.year
      end

      whole_units / count
    end
  end
end
