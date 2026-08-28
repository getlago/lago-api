# frozen_string_literal: true

module BillingPeriods
  # The evenly spaced marks a billing calendar is laid out on, and the arithmetic over them:
  # where a period opens, where it closes, how many days it spans, which one an instant is in,
  # and what share of one a window covers.
  #
  # All of it in the customer's timezone, and every mark re-derived from the anchor so that
  # month-ends do not drift (Jan 31 -> Feb 28 -> Mar 31) instead of walking off the short one.
  #
  # It knows nothing about rates, phases, overrides or when anything is billed. Positions in,
  # numbers out.
  class Boundaries
    def initialize(billing_anchor_date:, interval_count:, interval_unit:, timezone:)
      @billing_anchor_date = billing_anchor_date
      @interval_count = interval_count
      @interval_unit = interval_unit.to_sym
      @timezone = timezone
    end

    # The boundary at `position` = anchor + position * interval. `step` turns a
    # position count into a unit count, so it works for any interval_count.
    #
    #   at(0)  => 2022-02-01 (the anchor)   at(1) => 2022-03-01   at(-1) => 2022-01-01
    #   quarterly (interval_count: 3), anchor Jan 1: at(2) => Jan 1 + 6.months => Jul 1
    def at(position)
      @at ||= {}
      @at[position] ||= boundary_at(position)
    end

    # The last instant of the period at `position`: the day before the next boundary, closed
    # out. Periods are inclusive at the end, so this is 23:59:59.999… and not the next mark.
    def ends_at(position)
      (at(position + 1) - 1.second).end_of_day
    end

    # What fraction of the period at `position` the window [from, to] covers, from 0 to 1.
    #
    # The denominator is the WHOLE period, never the window: a card starting on the 16th of a
    # 30-day month covers 15/30, not 15/15. The position is an argument rather than something
    # worked out from `from`, so this cannot quietly measure against a different period's
    # length than the caller meant.
    #
    # Arithmetic only. Whether the number is ever applied to money is a decision for the layer
    # that knows what proration is.
    def share_of(position, from, to)
      full = days_at(position)
      return 1 if full.zero?

      Utils::Datetime.date_diff_with_timezone(from, to, timezone).fdiv(full).clamp(0, 1)
    end

    # How many days the period at `position` spans, boundary to boundary.
    #   monthly, anchor Jun 1: days_at(0) => 30 (Jun 1 -> Jul 1)
    def days_at(position)
      (at(position + 1).to_date - at(position).to_date).to_i
    end

    # Which period `time` falls in: the last boundary on or before it.
    #
    # `time` moves into the customer timezone first, and it has to — the estimate reads
    # calendar fields off it, so 2026-02-28 16:00 UTC, already Mar 1 in Tokyo, would be read
    # as February and bill the wrong month. The estimate is then exact or one too high, never
    # too low, which is why stepping back once is enough. Positions go negative: a time before
    # the anchor is in an earlier period, so a card starting before its anchor day still bills.
    #
    #   anchor the 31st, position_on_or_before(Feb 15): estimate 1, but at(1) = Feb 28 > Feb 15
    #     => overshot => 0   (Feb 15 is in period 0, [Jan 31, Feb 28))
    #   anchor Jul 15, position_on_or_before(Jul 2): estimate 0, but at(0) = Jul 15 > Jul 2
    #     => overshot => -1  (Jul 2 is in period -1, [Jun 15, Jul 15))
    def position_on_or_before(time)
      local = time.in_time_zone(timezone)
      estimate = estimated_position(local)
      return estimate - 1 if at(estimate) > local

      estimate
    end

    # Boundary 0: the start of the anchor day, in the customer timezone.
    def anchor
      @anchor ||= billing_anchor_date.in_time_zone(timezone).beginning_of_day
    end

    # The customer's zone, which is what every mark and every day count above is measured in.
    attr_reader :timezone

    private

    attr_reader :billing_anchor_date, :interval_count, :interval_unit

    def boundary_at(position)
      step = position * interval_count

      case interval_unit
      when :day then anchor + step.days
      when :week then anchor + step.weeks
      when :month then anchor + step.months
      when :year then anchor + step.years
      else raise ArgumentError, "Invalid billing interval unit: #{interval_unit}"
      end
    end

    # A cheap guess: count whole calendar units from the anchor, then divide by the interval
    # count. Integer division floors toward negative infinity, which is what keeps the guess
    # exact or one too high — never too low — for times before the anchor as well.
    #   2022-03-15 => 1 month past => position 1
    #   quarterly, 7 months past   => 7 / 3 => position 2
    def estimated_position(local)
      whole_intervals = case interval_unit
      when :day then (local.to_date - anchor.to_date).to_i
      when :week then (local.to_date - anchor.to_date).to_i / 7
      when :month then ((local.year - anchor.year) * 12) + (local.month - anchor.month)
      when :year then local.year - anchor.year
      else raise ArgumentError, "Invalid billing interval unit: #{interval_unit}"
      end

      whole_intervals / interval_count
    end
  end
end
