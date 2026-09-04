# frozen_string_literal: true

module Billing
  # A ruler: boundaries every `interval` from the start of the anchor day, in the customer's timezone
  class Calendar
    # `anchor_date` is a date, and boundary 0 is the start of that day where the customer is:
    # anchored Feb 1 in "America/New_York", the ruler begins at Feb 1 05:00 UTC.
    def initialize(anchor_date:, interval:, timezone:)
      @anchor = anchor_date.in_time_zone(timezone).beginning_of_day
      @interval = interval
      @timezone = timezone
    end

    # The half-open interval `timestamp` falls in, as [boundary, next boundary).
    #
    # @example anchored Feb 1, monthly
    #   interval_containing(Feb 10)  # => 2022-02-01 00:00...2022-03-01 00:00
    def interval_containing(timestamp)
      index = interval_index(timestamp)

      interval_with_index_starts_at(index)...interval_with_index_starts_at(index + 1)
    end

    # Fraction of the interval containing `from` that the half-open window [from, to) covers.
    #
    # @example anchored Jun 1, monthly — a 30-day interval
    #   proration_ratio(Jun  1, Jul 1)  # => 1.0
    #   proration_ratio(Jun 28, Jul 1)  # => 0.1
    def proration_ratio(from, to)
      window = interval_containing(from)
      raise ArgumentError, "window end #{to} precedes its start #{from}" if to < from
      raise ArgumentError, "window [#{from}, #{to}) crosses the boundary at #{window.end}" if to > window.end

      covered_days(from, to).fdiv(covered_days(window.begin, window.end))
    end

    private

    attr_reader :anchor, :interval, :timezone

    # Which interval `timestamp` falls in — a position on this ruler, not a cycle number.
    #
    # @example anchored Jul 15, monthly
    #   interval_index(Jul  2)  # => -1   the anchor is a reference day, not a start date
    #   interval_index(Jul 15)  # =>  0
    #   interval_index(Aug 20)  # =>  1
    def interval_index(timestamp)
      interval.steps_between(anchor, timestamp.in_time_zone(timezone))
    end

    # The boundary at position `index`
    #
    # @example anchored Jan 31, monthly
    #   interval_with_index_starts_at(1)  # => Feb 28
    #   interval_with_index_starts_at(2)  # => Mar 31
    def interval_with_index_starts_at(index)
      @boundaries ||= {}
      @boundaries[index] ||= interval.advance(anchor, index)
    end

    # Days in the half-open window [from, to): a day belongs to the window holding its
    # midnight, so the day a window opens counts whole and the day it closes does not.
    #
    # Same instants as #opening_date below, which is what this subtracts.
    #
    # @example in "Europe/Paris"
    #   covered_days(Jun  1 00:00, Jun  1 09:30)  # =>  1   a day begun counts whole
    #   covered_days(Jun  1 00:00, Jun 16 09:30)  # => 16
    #   covered_days(Jun 16 09:30, Jul  1 00:00)  # => 14   the two sides sum to 30
    #   covered_days(Jun 16 09:30, Jun 16 23:59)  # =>  0   opens and closes inside a paid day
    #
    # @example a month one hour short, Paris springing forward on Mar 29
    #   covered_days(Mar  1 00:00, Apr  1 00:00)  # => 31   the 29th is 23 hours; still a day
    def covered_days(from, to)
      (opening_date(to) - opening_date(from)).to_i
    end

    # The first local date whose midnight is at or after `timestamp`. Compares against
    # midnight rather than adding a day, so a DST transition cannot shift the answer.
    #
    # Part-way through a day, the answer is tomorrow: the day in progress has already been
    # given to whatever window opened it, so the next one to hand out is the next.
    #
    # @example in "Europe/Paris" (UTC+2 in June)
    #   opening_date(Jun 16 09:30 Paris)  # => Jun 17   the 16th is spoken for
    #   opening_date(Jun 16 23:59 Paris)  # => Jun 17   still the 16th, however little is left
    #   opening_date(Jun 16 22:00 UTC)    # => Jun 17   midnight in Paris — local is what counts
    #   opening_date(Jun 16 23:00 UTC)    # => Jun 18   01:00 on the 17th there
    def opening_date(timestamp)
      local = timestamp.in_time_zone(timezone)

      (local == local.beginning_of_day) ? local.to_date : local.to_date + 1
    end
  end
end
