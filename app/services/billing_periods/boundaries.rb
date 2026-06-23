# frozen_string_literal: true

module BillingPeriods
  # The sequence of billing-period boundaries derived from an anchor and interval.
  #
  # Picture evenly spaced fenceposts on a timeline, starting at the anchor:
  #
  #   at(-1)      at(0)=anchor   at(1)         at(2)
  #     |------------|-------------|-------------|
  #              one interval  one interval
  #
  # Boundaries are `anchor + index * interval`, always re-derived from the anchor
  # (never incremented from the previous one) so month/year anchoring never drifts
  # (Jan 31 -> Feb 28 -> Mar 31, not Mar 28). Everything is computed in the customer
  # timezone. Plain value object shared by the billing-time and creation-time services.
  #
  # Running example used below: anchor 2022-02-01, monthly (interval_count: 1), UTC.
  class Boundaries
    def initialize(billing_anchor_date:, interval_count:, interval_unit:, timezone:)
      @billing_anchor_date = billing_anchor_date
      @interval_count = interval_count
      @interval_unit = interval_unit.to_sym
      @timezone = timezone
    end

    # The boundary at the given index (may be negative), in the customer timezone.
    # Index 0 is the anchor, 1 is one interval later, -1 is one interval earlier.
    #
    #   at(0)  => 2022-02-01   (the anchor)
    #   at(1)  => 2022-03-01
    #   at(-1) => 2022-01-01
    #
    # `step` converts a boundary index into a count of units: for quarterly
    # (interval_count: 3) anchored at Jan 1, at(2) => Jan 1 + 6.months => Jul 1.
    def at(index)
      step = index * interval_count

      case interval_unit
      when :day then anchor + step.days
      when :week then anchor + step.weeks
      when :month then anchor + step.months
      when :year then anchor + step.years
      end
    end

    # Index of the period that contains `time`: the largest index whose boundary is
    # on or before it. This is the value you feed back into `at`.
    #
    #   index_on_or_before(2022-03-15) => 1   (Mar 1 <= Mar 15 < Apr 1)
    #   index_on_or_before(2022-02-01) => 0   (exactly on the anchor)
    #
    # `estimated_index` is a cheap guess that counts whole calendar months and so is
    # exact when `time`'s day is on or after the anchor's, and exactly one too high
    # otherwise (that month's boundary -- e.g. the 31st -- hasn't been reached yet).
    # It can never be too low, because at(estimate + 1) is always a later month than
    # `time`. So we only ever step down by one. Example (anchor on Jan 31):
    #
    #   index_on_or_before(Feb 15): estimate=1, but at(1)=Feb 28 > Feb 15 -> step to 0
    def index_on_or_before(time)
      estimate = estimated_index(time)
      return estimate - 1 if estimate.positive? && at(estimate) > time

      estimate
    end

    # The reference point -- boundary 0 -- as the start of the anchor day in the
    # customer timezone.
    #
    #   billing_anchor_date 2022-02-01, "America/New_York"
    #     => 2022-02-01 00:00 New York (== 2022-02-01 05:00 UTC)
    def anchor
      @anchor ||= billing_anchor_date.in_time_zone(timezone).beginning_of_day
    end

    private

    attr_reader :billing_anchor_date, :interval_count, :interval_unit, :timezone

    # A cheap estimate of the boundary index for `time`, used as the starting point
    # for `index_on_or_before`. Counts whole calendar units between the anchor and
    # `time`, then divides by interval_count to turn a unit count into a boundary
    # index.
    #
    #   time 2022-03-15: whole_intervals = 1 month  -> index 1
    #   quarterly (count 3), time 7 months past anchor: 7 / 3 -> index 2
    #
    # Floored at 0 so a `time` before the anchor never produces a negative index
    # (we never resolve a period earlier than the first one).
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
