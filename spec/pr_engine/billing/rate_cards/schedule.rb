# frozen_string_literal: true

# Vendored from app/services/billing/rate_cards/schedule.rb on PR getlago/lago-api#6267
# (branch `engine-dates`). Only the outermost module and the cross-namespace constant
# references are re-rooted under `PrEngine::`; every method body below is the PR's own,
# EXCEPT the two blocks marked `PARITY DELTA`.
#
# =======================================================================================
# PARITY DELTA — THIS FILE IS NO LONGER VERBATIM.
#
# Added 2026-09-04 by the three-way comparison (`pr-parity`), NOT by PR 6267's author, so
# that the adversarial review of the two designs argues about the design difference and
# not about a hole in the vendored copy. Two additions, each also marked inline:
#
#   Gap 1 — `Cycle#consumed_ratio(segment, at)`. The capability
#           `V2::Subscriptions::CreditUnusedAdvanceService` consumes and that PR 6267's own
#           parity spec records as missing: "consumed_ratio — the old Period carried it;
#           this engine has no equivalent yet". Given here in this engine's own shape: on
#           `Cycle`, which already holds the calendar and already answers
#           `#proration_ratio(segment)`.
#
#   Gap 2 — `#cycles_overlapping` now honours `Range#exclude_end?` and keeps the cycle that
#           opens exactly on an INCLUSIVE range end. That is the answer `cycles_due_by` in
#           this same class already gives for the same cycle at the same instant (it breaks
#           on `due_at > timestamp`, and for an advance cycle `due_at` IS `started_at`), so
#           the fix makes the class agree with itself.
#
# Nothing else is touched. In particular the per-CYCLE release gate in `#walk_from`, the
# `Float`/`fdiv` arithmetic, the `RateCards::` namespace, every name and the constructor
# arity are all exactly as the PR wrote them.
# =======================================================================================
module PrEngine; end

module PrEngine::Billing
  module RateCards
    class Schedule
      TIMINGS = %i[advance arrears].freeze

      Phase = Data.define(:position, :cycle_count, :code, :override) do
        # The card on its own cadence, unbounded and unpriced by any override. It has no
        # position because nothing persisted it — being last is what defines it.
        def self.default = new(position: nil, cycle_count: nil, code: nil, override: nil)
      end

      # What the card charges for a window: which end of it falls due, and whether a partial
      # one is prorated. Constant for the whole schedule.
      Terms = Data.define(:timing, :prorated) do
        def billing_at(window) = (timing == :advance) ? window.started_at : window.ended_at

        def share_of(calendar, window)
          prorated ? calendar.proration_ratio(window.started_at, window.ended_at) : 1.0
        end
      end

      # `ended_at` is exclusive, matching Segment and not the column of the same name.
      Cycle = Data.define(:index, :started_at, :ended_at, :phase, :calendar, :terms) do
        private :calendar, :terms

        def due_at = terms.billing_at(self)

        delegate :billing_at, to: :terms

        def segments(rates:) = Segments.within(started_at...ended_at, rates:)

        def proration_ratio(segment) = terms.share_of(calendar, segment)

        # PARITY DELTA (gap 1) — not PR 6267's code; see the file header.
        #
        # The share of this cycle consumed at `at`, measured from `segment`'s own start
        # against this cycle's calendar. Advance bills a slice up front, so a card ending
        # mid-cycle credits back the complement of this number.
        #
        # Measured from the segment rather than from the cycle's open so that a cycle cut
        # by a rate change stays honest: the piece after the change was never charged for
        # the piece before it. The two readings coincide on an uncut cycle.
        #
        # Deliberately NOT routed through `terms`: `share_of` answers "what do we charge
        # for this window", which an unprorated card answers with 1. This answers "how
        # much of it has been used", which is a fact about the calendar and not about the
        # terms — and it is how the old `Period#consumed_ratio` computed it too.
        def consumed_ratio(segment, at) = calendar.proration_ratio(segment.started_at, at)
      end

      def initialize(anchor_date:, phases:, rates:, prorated:, timezone:, starts_at:, timing:,
        ends_at: nil, realign_billing_anchor: true)
        @anchor_date = anchor_date
        @phases = ordered(phases)
        @rates = rates
        @realign_billing_anchor = realign_billing_anchor
        @timezone = timezone
        @starts_at = starts_at.in_time_zone(timezone).beginning_of_day
        @ends_at = ends_at
        @timing = timing.to_sym

        validate!

        @terms = Terms.new(timing: @timing, prorated:)
      end

      def cycles_due_by(timestamp)
        due, _pending = walk(timestamp)
        due
      end

      # PARITY DELTA (gap 2) — not PR 6267's code; see the file header. The PR's own body was
      #
      #   cycles_due_by(range.end)
      #     .select { |cycle| cycle.ended_at > range.begin && cycle.started_at < range.end }
      #
      # which always treated `range.end` as exclusive and so dropped the cycle opening on it.
      def cycles_overlapping(range)
        cycles_due_by(range.end).select { |cycle| overlapping?(cycle, range) }
      end

      def due_after(timestamp)
        _due, pending = walk(timestamp)
        pending&.due_at
      end

      def next_billing_at(timestamp)
        due, pending = walk(timestamp)

        due.find { |cycle| cycle.ended_at > timestamp }&.due_at || pending&.due_at
      end

      private

      attr_reader :anchor_date, :phases, :rates, :terms, :realign_billing_anchor, :timezone, :starts_at, :ends_at, :timing

      # Both consumers of this engine read the walk twice — /cycles serializes the windows
      # and reports the next billing instant, /bill writes the rows and advances the clock.
      # The previous engine memoized its own walk for the same reason.
      def walk(timestamp)
        @walks ||= {}
        @walks[timestamp] ||= walk_from(timestamp)
      end

      def walk_from(timestamp)
        cursor = starts_at
        index = 0
        due = []
        pending = nil

        anchor = anchor_date
        cadence = nil

        phases.each do |phase|
          break if pending || ended?(cursor)

          produced = 0

          while phase.cycle_count.nil? || produced < phase.cycle_count
            break if ended?(cursor)

            rate = cadence_rate_at(cursor)
            break unless rate

            interval = Interval.from(rate, override: phase.override)
            anchor = cursor.in_time_zone(timezone).to_date if realign_billing_anchor && cadence && cadence != interval
            cadence = interval

            calendar = calendar_for(anchor, interval)
            window = calendar.interval_containing(cursor)
            cycle = cycle_for(window, cursor, index, phase, calendar)
            if cycle.due_at > timestamp
              pending = cycle
              break
            end

            due << cycle
            cursor = window.end
            index += 1
            produced += 1
          end
        end

        [due, pending]
      end

      # The billing order is the phases' own, not the caller's. Sorting here rather than
      # trusting the list means a phase cannot be billed out of sequence by whoever built
      # it; an unpositioned phase is the synthesized default and belongs last. sort_by is
      # not stable, so the given order breaks ties.
      def ordered(phases)
        phases.each_with_index
          .sort_by { |phase, index| [phase.position || Float::INFINITY, index] }
          .map(&:first)
      end

      # One ruler per (anchor, interval) rather than one per cycle: a card that never changes
      # cadence builds a single Calendar however many cycles it walks.
      def calendar_for(anchor, interval)
        @calendars ||= {}
        @calendars[[anchor, interval]] ||= Calendar.new(anchor_date: anchor, interval:, timezone:)
      end

      def cadence_rate_at(cursor)
        Segments.rate_at(rates, cursor) || rates.min_by(&:effective_from)
      end

      def ended?(cursor)
        ends_at.present? && cursor >= ends_at
      end

      # PARITY DELTA (gap 2) — not PR 6267's code; see the file header.
      #
      # A cycle and a range overlap when each begins before the other ends. A cycle's window
      # is half-open; the caller's range need not be, and the two forms ask different
      # questions: `a..b` asks about the instant `b`, `a...b` stops short of it. Keeping the
      # cycle that opens exactly on an inclusive `b` is what `cycles_due_by(b)` already does
      # with that same cycle — it breaks on `due_at > timestamp`, and for an advance cycle
      # `due_at` IS `started_at`.
      def overlapping?(cycle, range)
        return false if cycle.ended_at <= range.begin
        return cycle.started_at < range.end if range.exclude_end?

        cycle.started_at <= range.end
      end

      def cycle_for(window, cursor, index, phase, calendar)
        started_at = [window.begin, cursor].max
        ended_at = ends_at ? [window.end, ends_at].min : window.end

        Cycle.new(index:, started_at:, ended_at:, phase:, calendar:, terms:)
      end

      def validate!
        raise ArgumentError, "Unknown billing timing: #{timing.inspect}" unless TIMINGS.include?(timing)
        raise ArgumentError, "ends_at #{ends_at} precedes starts_at #{starts_at}" if ends_at && ends_at < starts_at
        raise ArgumentError, "at least one phase is required" if phases.empty?
        raise ArgumentError, "the last phase must run to the end of the schedule" if phases.last.cycle_count
        raise ArgumentError, "only the last phase may run to the end" if phases[..-2].any? { |phase| phase.cycle_count.nil? }
      end
    end
  end
end
