# frozen_string_literal: true

module Billing
  class Calendar
    def initialize(anchor_date:, interval:, timezone:)
      @anchor_date = anchor_date
      @interval = interval
      @timezone = timezone
    end

    # Boundary 0: the start of the anchor day in the customer timezone.
    # @example anchor 2022-02-01 in "America/New_York" is 2022-02-01 05:00 UTC
    def anchor
      @anchor ||= anchor_date.in_time_zone(timezone).beginning_of_day
    end

    # The index of the period `time` falls in, negative before the anchor. A position on
    # this ruler, not a billing cycle number.
    # @example anchored on Jul 15: index_at(Jul 2) is -1, the period [Jun 15, Jul 15)
    def index_at(time)
      interval.steps_between(anchor, time.in_time_zone(timezone))
    end

    # The half-open period `time` falls in, as [boundary, next boundary).
    # @example anchored on Feb 1: period_at(Feb 10) is 2022-02-01...2022-03-01
    def period_at(time)
      index = index_at(time)

      at(index)...at(index + 1)
    end

    # Days in the whole period `time` falls in, whether or not the window covers it all.
    # @example anchored on Jun 1 monthly: days_in_period_at(Jun 10) is 30
    def days_in_period_at(time)
      days_in(period_at(time))
    end

    # Fraction of its period the half-open window [from, to) covers. The window must sit
    # inside one period: measuring across a boundary would divide by the wrong length.
    # @example in a 30-day period: [Jun 1, Jul 1) is 1.0, [Jun 28, Jul 1) is 0.1
    def elapsed_ratio(from, to)
      period = period_at(from)
      raise ArgumentError, "window end #{to} precedes its start #{from}" if to < from
      raise ArgumentError, "window [#{from}, #{to}) crosses the boundary at #{period.end}" if to > period.end

      covered_days(from, to).fdiv(days_in(period))
    end

    private

    attr_reader :anchor_date, :interval, :timezone

    # The boundary at position `index`, re-derived from the anchor so month-ends don't drift.
    # @example anchored on Jan 31: at(1) is Feb 28, at(2) is Mar 31
    def at(index)
      interval.advance(anchor, index)
    end

    # @example a 30-day period: days_in(Jun 1...Jul 1) is 30
    def days_in(period)
      (period.end.to_date - period.begin.to_date).to_i
    end

    # Utils::Datetime counts between inclusive bounds, so the exclusive end is pulled back.
    # @example [Jun 1, Jul 1) is 30 days; without the second it would be 31
    def covered_days(from, to)
      Utils::Datetime.date_diff_with_timezone(from, to - 1.second, timezone)
    end
  end
end
