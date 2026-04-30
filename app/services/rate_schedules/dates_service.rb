# frozen_string_literal: true

module RateSchedules
  class DatesService
    def initialize(subscription_rate_schedule:, billing_at: nil, current_usage: false)
      @srs = subscription_rate_schedule
      @billing_at = billing_at
      @current_usage = current_usage
    end

    def from_datetime
      cycle_start(cycle_index)
    end

    def to_datetime
      next_cycle_start = cycle_start(cycle_index + 1)
      ended_at = srs.ended_at

      if ended_at && ended_at < next_cycle_start
        ended_at
      else
        (next_cycle_start - 1.day).end_of_day
      end
    end

    def cycle_index
      return 0 if billing_at <= srs.started_at

      i = 0
      i += 1 while cycle_start(i + 1) <= billing_at
      i
    end

    private

    attr_reader :srs, :billing_at, :current_usage

    def cycle_start(index)
      return started_at_beginning_of_day if index.zero?

      full_cycle_index = has_partial_first_cycle? ? index - 1 : index
      units = full_cycle_index * rate_schedule.billing_interval_count

      case rate_schedule.billing_interval_unit
      when "day" then first_full_cycle_start + units.days
      when "week" then first_full_cycle_start + units.weeks
      when "month" then monthly_full_cycle(units)
      when "year" then yearly_full_cycle(units)
      end
    end

    def started_at_beginning_of_day
      @started_at_beginning_of_day ||= srs.started_at.beginning_of_day
    end

    # Returns the stored billing_anchor_date, falling back to started_at when nil
    # (equivalent to "no anchor": cycles align naturally to the start date).
    def billing_anchor_date
      srs.billing_anchor_date || srs.started_at.to_date
    end

    # Returns midnight UTC for (year, month, anchor_day), clamping the day to the
    # last day of the month when anchor_day exceeds the days in that month.
    #
    # `Date.new(year, month, -1)` returns the last day of that month
    # (Ruby treats negative day arguments as offsets from the end of the month).
    # Examples:
    #   Date.new(2026, 2, -1).day → 28  (February in non-leap year)
    #   Date.new(2024, 2, -1).day → 29  (February in leap year)
    #   Date.new(2026, 4, -1).day → 30  (April)
    #
    #   clamp_month_anchor(2026, 2, 31) → Feb 28 2026  (clamped)
    #   clamp_month_anchor(2024, 2, 29) → Feb 29 2024  (leap, no clamp)
    #   clamp_month_anchor(2026, 3, 31) → Mar 31 2026  (no clamp)
    def clamp_month_anchor(year, month, anchor_day)
      days_in_month = Date.new(year, month, -1).day
      Time.zone.local(year, month, [anchor_day, days_in_month].min)
    end

    # True when started_at lands BEFORE the first full cycle, meaning cycle 0
    # is a shorter partial cycle bridging started_at to first_full_cycle_start.
    # False when there's no partial: cycle 0 IS the first full cycle.
    #
    #   started Jan 5,  anchor day 15        → first = Jan 15  → true  (partial: Jan 5–14)
    #   started Jan 15, anchor day 15        → first = Jan 15  → false (aligned)
    #   started any,    anchor = nil         → first = started → false (no anchor → fallback aligns)
    #   started any,    unit = "day"         → first = started → false (daily ignores anchor)
    def has_partial_first_cycle?
      first_full_cycle_start != started_at_beginning_of_day
    end

    # Start of the first full cycle: the first instant where the anchor rule
    # lands on or after started_at. Dispatched by interval unit.
    # Memoized because cycle_start (called many times by cycle_index) reuses it.
    def first_full_cycle_start
      @first_full_cycle_start ||= compute_first_full_cycle_start
    end

    def compute_first_full_cycle_start
      case rate_schedule.billing_interval_unit
      when "day" then started_at_beginning_of_day # daily ignores anchor
      when "week" then weekly_first_full_cycle_start
      when "month" then monthly_first_full_cycle_start
      when "year" then yearly_first_full_cycle_start
      end
    end

    # First date matching the anchor's wday on or after started_at.
    # If started_at already lands on that wday, returns started_at_beginning_of_day (aligned).
    #
    # The trick is `(anchor.wday - base.wday) % 7`. Ruby's `%` on negatives is
    # non-negative, so a "past" wday wraps forward to the following week.
    # wday: 0=Sun, 1=Mon, ..., 6=Sat
    #
    #   started_at = Mon (1), anchor.wday = 4 (Thu) → (4 - 1) % 7 = 3 → +3.days → Thursday
    #   started_at = Fri (5), anchor.wday = 3 (Wed) → (3 - 5) % 7 = 5 → +5.days → next Wednesday
    #   started_at = Wed (3), anchor.wday = 3 (Wed) → (3 - 3) % 7 = 0 → +0.days → aligned
    def weekly_first_full_cycle_start
      diff = (billing_anchor_date.wday - started_at_beginning_of_day.wday) % 7
      started_at_beginning_of_day + diff.days
    end

    # First date matching the anchor's day-of-month on or after started_at.
    # Tries the started_at's own month first; if the anchor day has already
    # passed there, jumps to the following month. Two months are always
    # enough to cover any case (anchor day occurs at most once per month).
    #
    #   started Jan 5,  anchor day 15 → clamp(2026, 1, 15) = Jan 15 ≥ Jan 5  → Jan 15  (10-day partial)
    #   started Jan 20, anchor day 15 → clamp(2026, 1, 15) = Jan 15 < Jan 20 → Feb 15  (26-day partial)
    #   started Jan 15, anchor day 15 → clamp(2026, 1, 15) = Jan 15 = Jan 15 → Jan 15  (aligned)
    #   started Feb 5,  anchor day 31 → clamp(2026, 2, 31) = Feb 28 ≥ Feb 5  → Feb 28  (clamped)
    def monthly_first_full_cycle_start
      base = started_at_beginning_of_day
      candidate = clamp_month_anchor(base.year, base.month, billing_anchor_date.day)
      return candidate if candidate >= base

      next_month = base.next_month
      clamp_month_anchor(next_month.year, next_month.month, billing_anchor_date.day)
    end

    # First date matching the anchor's (month, day) on or after started_at.
    # Tries the started_at's own year first; if the anchor date has already
    # passed there, jumps to the following year. Reuses clamp_month_anchor
    # to handle the Feb 29 edge case in non-leap years.
    #
    #   started Feb 1 2026,  anchor 2025-03-15 → clamp(2026, 3, 15) = Mar 15 2026 ≥ base → Mar 15 2026
    #   started Apr 1 2026,  anchor 2025-03-15 → clamp(2026, 3, 15) = Mar 15 2026 < base → Mar 15 2027
    #   started Mar 15 2026, anchor 2025-03-15 → clamp(2026, 3, 15) = Mar 15 2026 = base → aligned
    #   started Feb 27 2026, anchor 2024-02-29 → clamp(2026, 2, 29) = Feb 28 2026 ≥ base → Feb 28 2026 (clamped)
    #   started Mar 1 2026,  anchor 2024-02-29 → clamp(2026, 2, 29) = Feb 28 2026 < base → Feb 28 2027 (clamped)
    def yearly_first_full_cycle_start
      base = started_at_beginning_of_day
      candidate = clamp_month_anchor(base.year, billing_anchor_date.month, billing_anchor_date.day)
      return candidate if candidate >= base

      clamp_month_anchor(base.year + 1, billing_anchor_date.month, billing_anchor_date.day)
    end

    # Returns the start of a future full cycle, `units` months after first_full_cycle_start.
    # When first_full_cycle_start was clamped (e.g., anchor 31 → Feb 28), every subsequent
    # cycle re-projects the canonical anchor day so the original day is restored in months
    # that fit it (Mar 31, May 31, ...) and clamped where needed (Apr 30, Jun 30, ...).
    # When there was no clamp, Rails arithmetic preserves the anchor day correctly.
    #
    #   anchor 31, started Feb 5  → first = Feb 28 (clamped)
    #     cycle 2: clamp(2026, 3, 31) = Mar 31  (re-projected, restores 31)
    #     cycle 3: clamp(2026, 4, 31) = Apr 30  (re-projected, clamps to 30)
    #
    #   anchor 15, started Jan 5  → first = Jan 15 (no clamp)
    #     cycle 2: Jan 15 + 1.month = Feb 15
    #     cycle 3: Jan 15 + 2.months = Mar 15
    def monthly_full_cycle(units)
      next_date = first_full_cycle_start + units.months

      if first_full_cycle_start.day < billing_anchor_date.day
        clamp_month_anchor(next_date.year, next_date.month, billing_anchor_date.day)
      else
        next_date
      end
    end

    # Returns the start of a future full cycle, `units` years after first_full_cycle_start.
    # Same heuristic as monthly_full_cycle but for years: the only clamp case is
    # Feb 29 in non-leap years. When first_full_cycle_start was clamped (29 → 28),
    # we re-project so leap years restore to Feb 29.
    #
    #   anchor Feb 29 2024 (leap), started Mar 1 2024
    #     first = Feb 28 2025 (clamped, non-leap)
    #     cycle 2: clamp(2026, 2, 29) = Feb 28 2026
    #     cycle 4: clamp(2028, 2, 29) = Feb 29 2028  (leap, restored)
    #
    #   anchor Mar 15, started Feb 1 2026
    #     first = Mar 15 2026 (no clamp)
    #     cycle 2: Mar 15 2026 + 1.year = Mar 15 2027
    def yearly_full_cycle(units)
      next_date = first_full_cycle_start + units.years

      if first_full_cycle_start.day < billing_anchor_date.day
        clamp_month_anchor(next_date.year, next_date.month, billing_anchor_date.day)
      else
        next_date
      end
    end

    def rate_schedule
      srs.rate_schedule
    end
  end
end
