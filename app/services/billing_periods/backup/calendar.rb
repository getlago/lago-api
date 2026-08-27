# frozen_string_literal: true

module BillingPeriods
  # Which periods a billing run has to look at.
  #
  # One question decides how they are found: is every period the same length? If it is, the
  # whole calendar sits on one ruler and the ones around the range are read straight off it by
  # position. If a rate or a phase override changes the interval partway through, there is
  # nothing to index into and they have to be produced in order instead.
  #
  # The two produce the same periods — calendar_spec drives identical inputs through both and
  # compares them field by field. Reading by position exists only for speed, and it is worth a
  # lot of it: a twenty-year-old card costs the same as a six-month-old one, where walking to
  # it grows with every period in between.
  class Calendar
    def initialize(anchor:, started_at:, range:, timezone:, timing:, rates:, rate_phases:,
      reanchor_on_interval_change: true)
      @anchor = anchor
      @started_at = started_at
      @range = range
      @timezone = timezone
      @timing = timing
      @rates = rates
      @rate_phases = rate_phases
      @reanchor_on_interval_change = reanchor_on_interval_change
    end

    def periods
      return [] if rates.empty?

      evenly_spaced? ? indexed_periods : walked_periods
    end

    # Read straight off one ruler. A period of slack on each side: arrears bills the one that
    # closed BEFORE the range opened, and a period opening on its last day still counts.
    def indexed_periods
      (first_position..last_position).filter_map do |position|
        period = period_on(uniform_ruler, position, cycle: cycle_at(position))

        period if timing.due?(period)
      end
    end

    # Produced in order, re-reading the interval at each step. Three things travel with the
    # walk, and they are why this cannot be a map:
    #
    #   cursor     where the next period opens — the timing decides, and arrears differs
    #   cycle      how many periods in we are, which selects the rate phase
    #   previous   the interval last used, so a change to it can be noticed
    #   in_force   the anchor the calendar is currently laid out from, which a change moves
    def walked_periods
      due = []
      cursor = calendar_start
      cycle = 0
      in_force = anchor
      previous = nil

      loop do
        # The phase is read once and handed on: it picks the interval AND travels with the
        # period, and finding it is a scan of the phase list.
        phase = rate_phases.rate_phase_for_cycle(cycle)
        interval = interval_at(cursor, phase)
        break unless interval

        in_force = cursor.in_time_zone(timezone).to_date if reanchor?(previous, interval)

        period = period_at(cursor, cycle, interval:, anchor: in_force, rate_phase: phase)
        break if beyond_range?(period)

        due << period if timing.due?(period)

        moves_to = timing.next_period_start_for(period)
        break if moves_to <= cursor

        cursor = moves_to
        cycle += 1
        previous = interval
      end

      due
    end

    private

    attr_reader :anchor, :started_at, :range, :timezone, :timing, :rates, :rate_phases,
      :reanchor_on_interval_change

    delegate :begin, :end, to: :range, prefix: true

    # Every period the same length. A phase overriding the interval breaks that even when the
    # rates all agree, and one is enough — count or unit, either half does it.
    def evenly_spaced?
      return false unless rates.uniform_interval

      rate_phases.phases.none? do |phase|
        phase.rate_override&.billing_interval_count || phase.rate_override&.billing_interval_unit
      end
    end

    # `position` is where the period sits on the ruler; `cycle` is how many periods into the
    # card's own calendar it is. They differ by wherever the card started, and only `cycle`
    # picks the rate phase.
    #
    # `not_before` covers a card that starts mid-period: the first period opens when the card
    # does, not when the boundary did.
    def period_on(boundaries, position, cycle:, not_before: calendar_start,
      rate_phase: rate_phases.rate_phase_for_cycle(cycle))
      Period.new(
        index: cycle,
        starts_at: [boundaries.at(position).utc, not_before].max,
        ends_at: boundaries.ends_at(position).utc,
        next_billing_at: timing.next_billing_at_for(boundaries, position),
        rate_phase:,
        full_days: boundaries.days_at(position),
        timezone:
      )
    end

    # Rulers are cached per anchor and spacing: the walk re-asks for the same one at every
    # step, and each carries its own memo of the boundaries it has worked out.
    def ruler(count, unit, anchor:)
      @rulers ||= {}
      @rulers[[anchor, count, unit]] ||= Boundaries.new(
        billing_anchor_date: anchor,
        interval_count: count,
        interval_unit: unit,
        timezone:
      )
    end

    # Where this card's calendar begins.
    def calendar_start
      @calendar_start ||= started_at.in_time_zone(timezone).beginning_of_day.utc
    end

    # ── reading by position ──────────────────────────────────────────────────────────────

    def uniform_ruler
      @uniform_ruler ||= ruler(*rates.uniform_interval, anchor:)
    end

    # A ruler position is not a cycle number: they differ by wherever the card started.
    def cycle_at(position)
      position - origin_position
    end

    # Where the card's own calendar starts counting from.
    def origin_position
      @origin_position ||= uniform_ruler.position_on_or_before(calendar_start)
    end

    def first_position
      [uniform_ruler.position_on_or_before(range_begin) - 1, origin_position].max
    end

    def last_position
      uniform_ruler.position_on_or_before(range_end) + 1
    end

    # ── walking ──────────────────────────────────────────────────────────────────────────

    # The walk stops once a period sits past the range AND the timing agrees it is too late to
    # matter — arrears bills a period after it closes, so it lingers a while.
    def beyond_range?(period)
      period.starts_at > range_end && timing.past_range?(period)
    end

    def period_at(cursor, cycle, interval:, anchor:, rate_phase:)
      boundaries = ruler(*interval, anchor:)
      position = boundaries.position_on_or_before(cursor)

      period_on(boundaries, position, cycle:, not_before: cursor, rate_phase:)
    end

    # A changed interval restarts the calendar from here, when asked to.
    def reanchor?(previous, interval)
      reanchor_on_interval_change && previous && previous != interval
    end

    # The [count, unit] a period opening here is laid out with: what the rate dictates, unless
    # the phase covering this period overrides one half of it or both.
    def interval_at(opens_at, phase)
      interval = rates.interval_at(opens_at)
      return unless interval

      override = phase&.rate_override
      return interval unless override

      [override.billing_interval_count || interval.first,
        override.billing_interval_unit || interval.last]
    end
  end
end
