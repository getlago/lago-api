# frozen_string_literal: true

module Billing
  # A cadence: how far one billing period runs.
  class Interval < Data.define(:count, :unit)
    UNITS = %i[day week month year].freeze

    # The cadence a rate bills on, with an override laid over it field by field.
    #
    # @param override [RateOverride, nil] either column alone wins
    # @return [Interval]
    #
    # @example a `3 month` rate
    #   from(rate)                                   # => 3 month
    #   from(rate, override: unit week)              # => 3 week
    #   from(rate, override: count 2)                # => 2 month
    def self.from(rate, override: nil)
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

    # Move an instant by whole intervals.
    #
    # @param steps [Integer] may be negative
    # @return [Time] month-end clamped
    #
    # @example monthly
    #   advance(Jan 31, 1)   # => Feb 28   clamped, not Mar 3
    #   advance(Jan 15, -2)  # => Nov 15 of the year before
    def advance(timestamp, steps)
      units = count * steps

      case unit
      when :day then timestamp + units.days
      when :week then timestamp + units.weeks
      when :month then timestamp + units.months
      when :year then timestamp + units.years
      end
    end

    # Whole intervals between two instants.
    #
    # @return [Integer] may be negative
    #
    # @example monthly, and the correction that earns this method
    #   steps_between(Jan 31, Feb 15)  # => 0   the calendar changed month; a month has not passed
    #   steps_between(Jan 31, Feb 28)  # => 1   here it has
    #
    # @example every 3 months, and weekly
    #   steps_between(Jan 1, Aug 1)    # => 2   7 months hold two whole 3-month intervals
    #   steps_between(Jun 1, Jun 20)   # => 2   weekly
    def steps_between(from, to)
      estimate = calendar_steps_between(from, to)

      if advance(from, estimate) > to
        estimate - 1
      else
        estimate
      end
    end

    private

    # Whole units by the calendar, then how many intervals of `count` fit in them.
    #
    # @return [Integer] over by at most one, which #steps_between corrects
    #
    # @example monthly
    #   calendar_steps_between(Jan 31, Feb 15)  # => 1   the month number changed
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
