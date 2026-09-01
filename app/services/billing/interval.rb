# frozen_string_literal: true

module Billing
  # How long one billing cycle lasts: `count` calendar units of `unit`.
  #
  # @example Interval.new(count: 2, unit: :week)   is "every two weeks"
  # @example Interval.new(count: 1, unit: :month)  is "monthly"
  class Interval < Data.define(:count, :unit)
    UNITS = %i[day week month year].freeze

    # @example a monthly rate, and an override that only changes the unit
    #   rate     = billing_interval_count: 1,   billing_interval_unit: "month"
    #   override = billing_interval_count: nil, billing_interval_unit: "week"
    #   Interval.from(rate, override:)  # => Interval(count: 1, unit: :week)
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

    # `timestamp` moved by `steps` whole intervals.
    # @example monthly, from a month-end
    #   monthly = Interval.new(count: 1, unit: :month)
    #   monthly.advance(Jan 31, 1)   # => Feb 28   clamped, February is short
    #   monthly.advance(Jan 31, 2)   # => Mar 31   back to the 31st, no drift
    #   monthly.advance(Jan 31, -1)  # => Dec 31   negative steps walk backwards
    def advance(timestamp, steps)
      units = count * steps

      case unit
      when :day then timestamp + units.days
      when :week then timestamp + units.weeks
      when :month then timestamp + units.months
      when :year then timestamp + units.years
      end
    end

    # How many whole intervals fit between `from` and `to`. Negative when `to`
    # precedes `from`.
    #
    # @example monthly, counting from 2022-01-31
    #   where the steps land:  2021-12-31 | 2022-01-31 | 2022-02-28 | 2022-03-31
    #   steps_between(Jan 31, 2022-01-30)  # => -1   before where we started
    #   steps_between(Jan 31, 2022-02-15)  # =>  0   inside the first interval
    #   steps_between(Jan 31, 2022-02-27)  # =>  0   still inside, a day short of closing
    #   steps_between(Jan 31, 2022-02-28)  # =>  1   turns where the step lands
    def steps_between(from, to)
      estimate = calendar_steps_between(from, to)

      if advance(from, estimate) > to
        estimate - 1
      else
        estimate
      end
    end

    private

    # Whole intervals between `from` and `to` by calendar arithmetic alone: subtract the
    # unit, then divide by `count`. It never asks where a step would actually land, so near
    # a month-end it can come out one too high.
    #
    # @example monthly, from Jan 31 — two different dates, one answer
    #   calendar_steps_between(Jan 31, Feb 28)  # => 1
    #   calendar_steps_between(Jan 31, Feb 27)  # => 1
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
