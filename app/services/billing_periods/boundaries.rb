# frozen_string_literal: true

module BillingPeriods
  # Calculator for the evenly-spaced billing "fenceposts" that start at an anchor.
  # Given an anchor + interval it answers two questions: "where is boundary N?" and
  # "which boundary is a given time in?" — in the customer timezone, and always
  # re-derived from the anchor so month-ends don't drift (Jan 31 -> Feb 28 -> Mar 31).
  #
  # Running example below: anchor 2022-02-01, monthly (interval_count: 1), UTC.
  # The fenceposts are: ... Jan 1 | Feb 1 | Mar 1 | Apr 1 ...
  class Boundaries
    def initialize(billing_anchor_date:, interval_count:, interval_unit:, timezone:)
      @billing_anchor_date = billing_anchor_date
      @interval_count = interval_count
      @interval_unit = interval_unit.to_sym
      @timezone = timezone
    end

    # The boundary at position `index` = anchor + index * interval. `step` turns a
    # boundary count into a unit count, so it works for any interval_count.
    #
    #   at(0)  => 2022-02-01 (the anchor)   at(1) => 2022-03-01   at(-1) => 2022-01-01
    #   quarterly (interval_count: 3), anchor Jan 1: at(2) => Jan 1 + 6.months => Jul 1
    def at(index)
      step = index * interval_count

      case interval_unit
      when :day then anchor + step.days
      when :week then anchor + step.weeks
      when :month then anchor + step.months
      when :year then anchor + step.years
      end
    end

    # Which period `time` falls in: the largest index whose boundary is on or before
    # it (the value you pass back into `at`).
    #
    # `estimated_index` returns a value that is either exact or one too high (never
    # too low). The `if` is what catches the "one too high" case and steps back:
    #   - at(estimate) > time  => the guessed boundary is AFTER time, so it overshot
    #   - estimate.positive?   => guard so we never step below 0 (the first period)
    #
    # Example, anchor on the 31st, index_on_or_before(Feb 15):
    #   estimate = 1, but at(1) = Feb 28, which is > Feb 15  => overshot => return 0
    #   (Feb 15 is really in period 0: [Jan 31, Feb 28))
    def index_on_or_before(time)
      estimate = estimated_index(time)
      return estimate - 1 if estimate.positive? && at(estimate) > time

      estimate
    end

    # The reference point (boundary 0): the start of the anchor day in the customer tz.
    #   anchor for 2022-02-01 in "America/New_York" => 2022-02-01 00:00 NY (05:00 UTC)
    def anchor
      @anchor ||= billing_anchor_date.in_time_zone(timezone).beginning_of_day
    end

    # Days in the boundary-to-boundary period that `time` falls in (the legacy engine's
    # compute_duration equivalent).
    #   monthly, anchor Jun 1: full_period_days(Jun 10) => 30 (Jun 1 -> Jul 1)
    def full_period_days(time)
      index = index_on_or_before(time.in_time_zone(timezone))
      (at(index + 1).to_date - at(index).to_date).to_i
    end

    # Fraction the window [period_from, period_to] represents of its full period, capped
    # at 1. Billed days use the shared, timezone-aware date diff (same util the legacy
    # engine prorates with), so a partial window (clamped start or termination) prorates
    # and a full period is 1.
    #   [Jun 1, Jun 30] in a 30-day period => 1.0    [Jun 29, Jul 1] => 3/30 => 0.1
    def proration_ratio(period_from, period_to)
      full = full_period_days(period_from)
      return 1 if full.zero?

      [billed_days(period_from, period_to).fdiv(full), 1].min
    end

    private

    attr_reader :billing_anchor_date, :interval_count, :interval_unit, :timezone

    def billed_days(from, to)
      Utils::Datetime.date_diff_with_timezone(from, to, timezone)
    end

    # A cheap guess of the index: count whole calendar units from the anchor, then
    # divide by interval_count to turn that unit count into a boundary index.
    #
    #   2022-03-15 => 1 month past => index 1
    #   quarterly, 7 months past   => 7 / 3 => index 2
    #
    # Floored at 0 so a `time` before the anchor never yields a negative index.
    def estimated_index(time)
      whole_intervals = case interval_unit
      when :day then (time.to_date - anchor.to_date).to_i
      when :week then (time.to_date - anchor.to_date).to_i / 7
      when :month then ((time.year - anchor.year) * 12) + (time.month - anchor.month)
      when :year then time.year - anchor.year
      end

      [whole_intervals / interval_count, 0].max
    end
  end
end
