# frozen_string_literal: true

module Billing
  # A ruler: boundaries every `interval` from the start of the anchor day, in the customer's
  # timezone. Anchored Feb 1 in "America/New_York", boundary 0 is Feb 1 05:00 UTC.
  class Calendar
    attr_reader :anchor_date, :interval

    def initialize(anchor_date:, interval:, timezone:)
      @anchor_date = anchor_date
      @anchor = anchor_date.in_time_zone(timezone).beginning_of_day
      @interval = interval
      @timezone = timezone
    end

    # The half-open interval `timestamp` falls in, as [boundary, next boundary).
    def interval_containing(timestamp)
      index = index_of_interval(timestamp)

      interval_with_index_starts_at(index)...interval_with_index_starts_at(index + 1)
    end

    # How many intervals separate two instants on this ruler.
    #
    # @example a monthly ruler anchored Jan 31, whose boundaries clamp to Feb 28
    #   intervals_between(Feb 28, Mar 31)  # => 1
    #   intervals_between(Feb 28, Mar 28)  # => 0   still inside the interval that opened Feb 28
    def intervals_between(from, to)
      index_of_interval(to) - index_of_interval(from)
    end

    # The boundary `steps` intervals after the one containing an instant.
    #
    # @example a monthly ruler anchored Jan 31
    #   boundary_after(Feb 10, 2)  # => Mar 31
    def boundary_after(timestamp, steps)
      interval_with_index_starts_at(index_of_interval(timestamp) + steps)
    end

    # The first boundary at or after an instant — when a change landing mid-interval takes hold.
    #
    # @example a monthly ruler anchored Jan 1
    #   boundary_at_or_after(Feb 1)   # => Feb 1   already a boundary
    #   boundary_at_or_after(Feb 10)  # => Mar 1
    def boundary_at_or_after(timestamp)
      window = interval_containing(timestamp)

      (window.begin == timestamp) ? window.begin : window.end
    end

    # The share of its containing interval that the half-open window [from, to) covers.
    #
    # @return [Float] denominator is the CONTAINING interval, never a fixed 30 days (decision #55)
    #
    # @example a 30-day interval anchored Jun 1
    #   proration_ratio(Jun  1, Jul 1)  # => 1.0
    #   proration_ratio(Jun 16, Jul 1)  # => 0.5
    def proration_ratio(from, to)
      raise ArgumentError, "window end #{to} precedes its start #{from}" if to < from

      window = interval_containing(from)
      raise ArgumentError, "window [#{from}, #{to}) crosses the boundary at #{window.end}" if to > window.end

      Days.between(from, to, timezone:).fdiv(Days.between(window.begin, window.end, timezone:))
    end

    private

    attr_reader :anchor, :timezone

    # Which interval `timestamp` falls in — a position on this ruler, not a cycle number. The
    # anchor is a reference day, not a start date, so instants before it have negative indices.
    def index_of_interval(timestamp)
      interval.steps_between(anchor, timestamp.in_time_zone(timezone))
    end

    def interval_with_index_starts_at(index)
      @boundaries ||= {}
      @boundaries[index] ||= interval.advance(anchor, index)
    end
  end
end
