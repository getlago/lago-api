# frozen_string_literal: true

module Billing
  # A billing cadence as a value: "every month", "every 3 weeks".
  #
  # Pure calendar arithmetic. It knows nothing about timezones, rates or subscriptions —
  # both of its methods receive the timestamps they operate on, and hand back whatever
  # class they were given.
  class Interval < Data.define(:count, :unit)
    UNITS = %i[day week month year].freeze

    # The one adapter between the catalog and the engine, kept as a named constructor
    # rather than a resolver class that would exist to hold a single `||` pair.
    #
    # The two fields coalesce independently, so an override that sets only one half of the
    # cadence keeps the other half from the rate:
    #   rate "3 months" + override "(nil, week)" => 3 weeks
    #   rate "3 months" + override "(2, nil)"    => 2 months
    def self.for(rate, override: nil)
      new(
        count: override&.billing_interval_count || rate.billing_interval_count,
        unit: override&.billing_interval_unit || rate.billing_interval_unit
      )
    end

    def initialize(count:, unit:)
      unit = unit.to_sym if unit.respond_to?(:to_sym)

      raise ArgumentError, "unknown interval unit #{unit.inspect}, expected one of #{UNITS.join(", ")}" unless UNITS.include?(unit)
      raise ArgumentError, "interval count must be a positive integer, got #{count.inspect}" unless count.is_a?(Integer) && count.positive?

      super
    end

    # `timestamp` moved by `steps` whole intervals. Negative steps move backwards.
    #
    # Month and year steps are always measured from `timestamp` itself, never accumulated
    # one step at a time, so a month-end cadence clamps without drifting:
    #   from Jan 31: advance(_, 1) => Feb 28, advance(_, 2) => Mar 31
    #   (accumulating would give Feb 28 => Mar 28 and lose the 31st forever)
    def advance(timestamp, steps)
      units = steps * count

      case unit
      when :day then timestamp + units.days
      when :week then timestamp + units.weeks
      when :month then timestamp + units.months
      when :year then timestamp + units.years
      end
    end

    # The whole intervals that fit between the two timestamps: the largest `n` for which
    # `advance(from, n) <= to`. Negative when `to` precedes `from`.
    #
    # Both timestamps must be read in the same timezone; localising them is the caller's
    # job, since an interval does not know what a timezone is.
    #
    # The estimate is exact or one too high, never too low, so checking where the step
    # actually lands corrects it in one move. Month ends are what make it overshoot:
    #   from Jan 31, to Feb 27 => estimate 1, but advance(_, 1) is Feb 28 > Feb 27 => 0
    #   from Jan 31, to Feb 28 => estimate 1, and advance(_, 1) is Feb 28          => 1
    def steps_between(from, to)
      estimate = estimated_steps(from, to)

      if advance(from, estimate) > to
        estimate - 1
      else
        estimate
      end
    end

    private

    # Whole calendar units between the two timestamps, turned into a number of intervals.
    #
    # Time of day is ignored, which is precisely what makes this an upper bound: a step
    # landing later in the day than `to` is caught by the correction above. Integer
    # division floors toward negative infinity, so the "never too low" property survives
    # timestamps before the anchor.
    def estimated_steps(from, to)
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
