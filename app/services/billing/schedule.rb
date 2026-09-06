# frozen_string_literal: true

module Billing
  # The walk: phases x rates x calendars -> billable segments.
  #
  # A schedule is a lazy, ever-growing list of segments. Building one computes nothing;
  # each query walks forward just far enough to answer itself and keeps whatever it
  # produced, so asking twice costs the walk once.
  #
  # Every window here is half-open, [started_at, ended_at): ended_at is the first instant
  # NOT covered. Consecutive windows share that instant, which is what makes segments
  # contiguous with no gap and no overlap.
  #
  # No ActiveRecord and no clock: every timestamp arrives as an argument. Loading a card
  # out of the database is BuildScheduleService's job.
  class Schedule
    # One slice of one cycle, priced by one rate, due at one instant. This is the shape of
    # a billing_segments row and of the /cycles payload: the engine hands out data, never
    # a collaborator.
    BillableSegment = Data.define(
      :cycle_index,
      :cycle_started_at,
      :started_at,
      :ended_at,
      :billing_at,
      :rate,
      :rate_override,
      :proration_ratio
    )

    # A stretch of consecutive cycles priced under one override. `cycle_count` is how many
    # cycles the stretch lasts; nil means "for as long as the card runs", which is why an
    # unbounded phase can only be the last one.
    Phase = Data.define(:position, :cycle_count, :code, :override) do
      # The card on its own cadence, unpriced by any override. Being last is what defines
      # it, so it has no position.
      def self.default
        new(position: nil, cycle_count: nil, code: nil, override: nil)
      end

      def unbounded?
        cycle_count.nil?
      end
    end

    def initialize(anchor_date:, timezone:, starts_at:, ends_at:, terms:, rates:, phases:, anchor_policy:)
      @anchor_date = anchor_date
      @timezone = timezone
      @starts_at = starts_at
      @ends_at = ends_at
      @terms = terms
      @rates = rates
      @phases = billing_order(phases)
      @anchor_policy = anchor_policy

      @anchor = anchor_date
      @cursor = starts_at.in_time_zone(timezone).beginning_of_day
      @cycle_index = 0
      @segments = []
      @calendars_by_cycle_index = {}
      @calendar = nil
      @interval = nil
      # A card with no rate has no cadence to walk. Its schedule is empty rather than a
      # crash: BuildScheduleService already refuses to build one.
      @walking = !rates.empty?
    end

    # What the scheduler asks: everything the clock owes at `timestamp`.
    def segments_due_by(timestamp)
      walk_until_cycle_opens_after(timestamp)
      segments.select { it.billing_at <= timestamp }
    end

    # What termination and the /cycles preview ask: everything covering the range,
    # whether or not it has fallen due. A cycle in progress is here and not in
    # #segments_due_by; an arrears cycle that closed but has not been billed is in both.
    def segments_overlapping(range)
      walk_until_cycle_opens_after(range.end)
      segments.select { overlaps?(it, range) }
    end

    # The next instant the clock owes something, strictly after `after`.
    def next_billing_at(after:)
      walk_until_due_after(after)
      segments.find { it.billing_at > after }&.billing_at
    end

    # The share of `segment` consumed at `at`. Advance bills a segment up front, so a card
    # ending inside one credits back the complement of this.
    #
    # THE RULE: the credited fraction must be computed on the same basis the fee was priced
    # on. A segment is priced as its own share of its cycle, so what is left of it is a
    # share of the SEGMENT — elapsed segment days over billed segment days — not of the
    # cycle. Measuring elapsed segment days against the whole cycle refunds days the
    # segment before the rate change paid for. The two readings coincide whenever the cycle
    # was not cut, which is the common case.
    #
    # An instant outside the segment is a question about a different period, and answering
    # it would put a ratio below 0 or above 1 into a credit note. It refuses, exactly as
    # Calendar#proration_ratio refuses an instant outside the window it was asked about.
    def consumed_ratio(segment:, at:)
      if at < segment.started_at || at > segment.ended_at
        raise ArgumentError, "at (#{at}) is outside the segment (#{segment.started_at}...#{segment.ended_at})"
      end

      calendar = calendar_of(segment)
      billed_days = calendar.covered_days(segment.started_at, segment.ended_at)
      # A segment too short to cover a whole day was charged for no days, so it has none
      # left to refund.
      return 1r if billed_days.zero?

      Rational(calendar.covered_days(segment.started_at, at), billed_days)
    end

    private

    attr_reader :anchor_date, :timezone, :starts_at, :ends_at, :terms, :rates, :phases,
      :anchor_policy, :anchor, :segments, :cursor, :cycle_index, :calendar

    # Phases bill in their own order, not in the order the caller listed them, and the
    # unbounded phase closes the list. `Phase.default` is appended when every configured
    # phase is bounded, so the walk always finds a phase for any cycle index.
    def billing_order(configured)
      ordered = configured.sort_by { [it.position.nil? ? 1 : 0, it.position || 0] }
      validate_unbounded_phase_is_last!(ordered)

      ordered.last&.unbounded? ? ordered : ordered + [Phase.default]
    end

    # An unbounded phase never ends, so anything after it would never bill. Two unbounded
    # phases fail here too: the first of them is not last.
    def validate_unbounded_phase_is_last!(ordered)
      return if ordered[0..-2].none?(&:unbounded?)

      raise ArgumentError, "an unbounded phase must be the last phase"
    end

    # Produce every cycle that opens at or before `timestamp`, and no more. Nothing beyond
    # can matter to a question about `timestamp`: a segment never bills before its cycle
    # opens, and the cursor is where the next cycle would open.
    def walk_until_cycle_opens_after(timestamp)
      produce_cycle while walking? && cursor <= timestamp
    end

    # #next_billing_at cannot bound itself by the cursor: in arrears the answer is often
    # the close of the cycle already open, and in advance it is the open of the next one.
    # Walking until a produced segment bills past `after` is what makes the answer come
    # from the NEXT cycle's own cadence instead of from a boundary of the current one —
    # the cadence-change bug this engine fixes.
    def walk_until_due_after(after)
      produce_cycle while walking? && (segments.empty? || segments.last.billing_at <= after)
    end

    def walking?
      @walking
    end

    def produce_cycle
      phase = phase_for(cycle_index)
      align_calendar_to(Interval.for(cadence_rate_at(cursor), override: phase.override))

      window = cycle_window
      return stop_walking if window.end <= window.begin

      segments.concat(billable_segments_of(window, phase))
      @calendars_by_cycle_index[cycle_index] = calendar
      open_next_cycle_at(window.end)
    end

    # The cycle the cursor sits in, clipped to the card. It opens at the cursor — a card
    # starting mid-cycle bills from its start, not from the boundary before it — and it
    # closes at the card's end when the card ends first.
    def cycle_window
      cursor...[calendar.window_containing(cursor).end, ends_at].compact.min
    end

    # The next cycle opens where this one closed: windows are half-open, so the closing
    # instant is the opening one and no time is lost between cycles.
    def open_next_cycle_at(instant)
      @cursor = instant
      @cycle_index += 1
      stop_walking if ends_at && instant >= ends_at
    end

    def stop_walking
      @walking = false
    end

    def align_calendar_to(interval)
      return if interval == @interval

      # The first cycle measures from the card's own anchor — there is no previous cadence
      # for it to have changed from. Every later change asks the anchor policy where to
      # measure from, and the walk takes the date it is handed without knowing which policy
      # answered. That is what keeps a second mode free: see Billing::AnchorPolicy.
      @anchor = calendar.nil? ? anchor_date : anchor_policy.anchor_after_cadence_change(anchor, cursor_local_date)
      @calendar = Calendar.new(anchor_date: anchor, interval:, timezone:)
      @interval = interval
    end

    def cursor_local_date
      cursor.in_time_zone(timezone).to_date
    end

    def billable_segments_of(window, phase)
      rates.segments_within(window).map do |segment|
        BillableSegment.new(
          cycle_index:,
          cycle_started_at: window.begin,
          started_at: segment.started_at,
          ended_at: segment.ended_at,
          billing_at: billing_at_of(segment),
          rate: segment.rate,
          rate_override: phase.override,
          proration_ratio: proration_ratio_of(segment)
        )
      end
    end

    # Due dates are per segment, not per cycle: advance bills a slice when it opens,
    # arrears when it closes. So a cycle cut by a rate change bills the piece before the
    # change on that piece's own boundary rather than dragging it to the cycle's.
    #
    # The boundary alone, never clamped to the clock. The previous engine returned
    # `[boundary, Time.current].max`, which collapsed every elapsed cycle onto today and made
    # the answer depend on when it was asked. QA rejected that (LAGO-1797): the due date is
    # when the cycle actually triggers, independent of the requested window. A caller that
    # needs "now" for an overdue cycle applies it at the write, where the clock belongs.
    def billing_at_of(segment)
      case terms.timing
      when :advance then segment.started_at
      when :arrears then segment.ended_at
      end
    end

    # Always a share of the whole cycle, never of the clipped window: half a cycle billed
    # is half a cycle's price. An unprorated card pays the full price for whatever it got.
    def proration_ratio_of(segment)
      return 1r unless terms.prorated

      calendar.proration_ratio(segment.started_at, segment.ended_at)
    end

    # Phases are consecutive stretches of cycles: the first phase owns its own
    # `cycle_count` cycles, the next owns the stretch after that, and the unbounded phase
    # owns everything left. The list always ends with an unbounded phase, so every cycle
    # index lands somewhere.
    def phase_for(index)
      remaining = index

      phases.find do |phase|
        next true if phase.unbounded?

        remaining -= phase.cycle_count
        remaining.negative?
      end
    end

    # The rate whose cadence rules the cursor. A card can open before its first rate takes
    # effect — the price does not exist yet, but the cycles still have to be laid out — so
    # those early cycles borrow the cadence of the first rate there will ever be. They
    # bill nothing: a slice with no rate in force is dropped, not priced at zero.
    def cadence_rate_at(timestamp)
      rates.at(timestamp) || rates.earliest
    end

    # Two windows overlap when each begins before the other ends. The engine's windows are
    # half-open; the caller's range is not necessarily, and `a..b` asks about the instant
    # `b` while `a...b` stops short of it.
    def overlaps?(segment, range)
      return false if segment.ended_at <= range.begin
      return segment.started_at < range.end if range.exclude_end?

      segment.started_at <= range.end
    end

    # A consumed share is measured against the cycle the segment belongs to, so it needs
    # that cycle's ruler — the one the walk was holding when it produced the segment.
    def calendar_of(segment)
      @calendars_by_cycle_index.fetch(segment.cycle_index) do
        raise ArgumentError, "segment was not produced by this schedule"
      end
    end
  end
end
