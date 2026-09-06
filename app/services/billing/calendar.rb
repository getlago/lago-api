# frozen_string_literal: true

module Billing
  # The ruler the engine measures cycles against: boundaries every `interval` from the
  # start of the anchor day, in the customer's timezone.
  #
  # It answers two questions about time and nothing else — it does not know what a rate, a
  # phase, an override or a subscription is, and every instant it works on arrives as an
  # argument.
  #
  # Running example: anchor 2024-02-01, monthly, America/New_York. Boundary 0 is
  # Feb 1 00:00 in New York, which is 05:00 UTC, and the fenceposts are
  #   ... | Jan 1 | Feb 1 | Mar 1 | ...   each at local midnight.
  class Calendar
    def initialize(anchor_date:, interval:, timezone:)
      @anchor_date = anchor_date
      @interval = interval
      @timezone = timezone
      @boundaries = {}
    end

    # The half-open window `[boundary, next boundary)` that holds `timestamp`.
    #
    # Indices go negative: the anchor is a reference day, not a start date, so a timestamp
    # before it falls in an earlier window rather than in window 0.
    def window_containing(timestamp)
      index = index_containing(timestamp)

      boundary_at(index)...boundary_at(index + 1)
    end

    # The share of the window holding `from` that `[from, to)` covers.
    #
    # Returns a Rational, not a Float: this number is multiplied into money, and the
    # pieces of a cut cycle have to add up to exactly the cycle.
    #
    # It is a question about ONE window. A caller whose `to` crosses a boundary is asking
    # the wrong object, and gets an ArgumentError instead of a ratio above 1.
    def proration_ratio(from, to)
      raise ArgumentError, "to (#{to}) is before from (#{from})" if to < from

      window = window_containing(from)
      raise ArgumentError, "to (#{to}) is past the end of the window containing from (#{window.end})" if to > window.end

      Rational(covered_days(from, to), covered_days(window.begin, window.end))
    end

    # The whole days `[from, to)` covers.
    #
    # RULE: a day belongs to the window that holds its local midnight. A window therefore
    # counts the day it opens on only when it opens at midnight, and never counts the day
    # it closes on. That single rule is what makes the segments of a cut cycle sum to the
    # cycle rather than to more than it.
    #
    # In Europe/Paris:
    #   covered_days(Jun  1 00:00, Jul  1 00:00) == 30
    #   covered_days(Jun  1 00:00, Jun 16 09:30) == 16
    #   covered_days(Jun 16 09:30, Jul  1 00:00) == 14   # 16 + 14 == 30, the invariant
    #   covered_days(Jun 16 09:30, Jun 16 23:59) ==  0
    #   covered_days(Mar  1 00:00, Apr  1 00:00) == 31   # Mar 31 is 23h long; still a day
    def covered_days(from, to)
      midnights_before(to) - midnights_before(from)
    end

    private

    attr_reader :anchor_date, :interval, :timezone

    # Boundary 0: the start of the anchor day in the customer's timezone.
    #   2024-02-01 in America/New_York => Feb 1 00:00 -05:00, i.e. 05:00 UTC
    def anchor
      @anchor ||= anchor_date.in_time_zone(timezone).beginning_of_day
    end

    # Every boundary is re-derived from the anchor by whole steps, never accumulated, so a
    # month-end anchor does not drift: Jan 31 => Feb 28 => Mar 31, not Feb 28 => Mar 28.
    #
    # The cache needs neither invalidation nor a size cap: a Calendar is immutable, so a
    # boundary is a pure function of (anchor, interval, index) and can never go stale, and
    # one lives only for the walk it was built for, so the indices it is asked for are
    # bounded by the cycles of that walk. It pays for itself because a walk asks for the
    # boundary closing each cycle a second time, as the boundary opening the next one.
    def boundary_at(index)
      @boundaries[index] ||= interval.advance(anchor, index)
    end

    # The largest index whose boundary is at or before `timestamp`, which is exactly the
    # number of whole intervals between the anchor and it.
    def index_containing(timestamp)
      interval.steps_between(anchor, local(timestamp))
    end

    # How many local midnights lie strictly before `timestamp`, as a Julian day number so
    # that subtracting two of them gives the days between them.
    #
    # The test is against the day's own start rather than against midnight-plus-a-day,
    # which is what keeps the count right across DST: a 23-hour day still contributes
    # exactly one midnight, and on a day whose midnight happens twice the second one is
    # after the day started and so is not mistaken for the day's own boundary — the count
    # never goes backwards, and the pieces still telescope.
    def midnights_before(timestamp)
      local_time = local(timestamp)
      day_start = local_time.beginning_of_day

      local_time.to_date.jd + ((local_time == day_start) ? 0 : 1)
    end

    def local(timestamp)
      timestamp.in_time_zone(timezone)
    end
  end
end
