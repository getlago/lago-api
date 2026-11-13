# frozen_string_literal: true

module Billing
  module RateCards
    # Answers when a rate card bills. Cycles come from the walker; each cycle is cut at rate
    # changes into priced slices, and every question below is asked of those slices.
    class Schedule
      # `due_on_coverage_end` makes every slice fall due when its coverage ends, whatever the
      # terms' timing. Cards that regroup paid advance fees use it (see BillableSegment).
      def initialize(
        rates:, terms:, phases:, starts_at:, anchor_date:, timezone:,
        ends_at: nil, due_on_coverage_end: false
      )
        @rates = rates
        @terms = terms
        @due_on_coverage_end = due_on_coverage_end
        @walker = CycleWalker.new(rates:, phases:, starts_at:, anchor_date:, timezone:, ends_at:)
      end

      # Every slice from the card's start that the terms bill by the instant. It reads
      # `billing_at`, not `due_at`: it lists what is billed, not what an operation picks up.
      # A rate change can make a slice billable before its cycle ends.
      def segments_due_by(timestamp)
        cycles = walker.walk_to(timestamp)

        billable_segments_of(cycles).select do |segment|
          segment.billing_at <= timestamp
        end
      end

      # The cycle containing the instant, or nil once the schedule has ended.
      def cycle_at(timestamp)
        walker.resume(timestamp)
      end

      # The first slice still open at the instant, or falling due exactly on it. The second
      # case keeps an arrears slice that closes on a mid-cycle rate change owed at that change.
      # Only the cycle containing the instant is searched backwards: a slice of an earlier
      # cycle that closed on the instant is not returned.
      def first_obligation(at:)
        segments(from: at).find { it.ended_at > at || it.due_at == at }
      end

      # The first slice falling due strictly after a completed billing instant, so a slice
      # billed at that instant is never returned twice. `from` names the cycle to start
      # walking from, for a billing that belongs to an earlier cycle than its instant.
      # A block maps a slice to its due instant when the caller moves it.
      def next_obligation(after:, from: after)
        segments(from:).find { (block_given? ? yield(it) : it.due_at) > after }
      end

      # The slices of one cycle falling due after a completed billing and by the given instant:
      # what one operation of that cycle bills. `cycle_started_at` must be a cycle's own start.
      def segments_due_in_cycle(cycle_started_at, by:, after: nil)
        segments(from: cycle_started_at)
          .take_while { it.cycle_started_at == cycle_started_at }
          .select { (after.nil? || it.due_at > after) && it.due_at <= by }
          .to_a
      end

      # Find the priced slice serving this instant, regardless of which cycles
      # have already been written to billing_segments.
      def segment_covering(timestamp)
        cycle = walker.resume(timestamp)

        if cycle
          billable_segments_of([cycle]).find do |segment|
            (segment.started_at...segment.ended_at).cover?(timestamp)
          end
        end
      end

      private

      attr_reader :rates, :terms, :due_on_coverage_end, :walker

      # Every priced slice in billing order, from the cycle containing `from`. Lazy, because an
      # open-ended card has no last cycle: callers stop at the first slice that answers them.
      # Unpriced cycles yield nothing.
      def segments(from:)
        Enumerator.new do |yielder|
          cycle = walker.resume(from)

          while cycle
            billable_segments_of([cycle]).each { yielder << it }
            cycle = walker.cycle_after(cycle)
          end
        end.lazy
      end

      # Unpriced periods of a cycle are not billable.
      def billable_segments_of(cycles)
        cycles.flat_map do |cycle|
          Segments.within(cycle, rates:).select(&:rate).map { build_billable_segment(cycle:, segment: it) }
        end
      end

      def build_billable_segment(cycle:, segment:)
        proration_ratio = if terms.prorated
          cycle.calendar.proration_ratio(segment.started_at, segment.ended_at)
        else
          1.0
        end

        billing_at = terms.billing_at_for(segment)

        BillableSegment.new(
          cycle_index: cycle.index,
          cycle_started_at: cycle.started_at,
          started_at: segment.started_at,
          ended_at: segment.ended_at,
          billing_at:,
          due_at: due_on_coverage_end ? segment.ended_at : billing_at,
          rate: segment.rate,
          rate_override: cycle.phase.rate_override,
          proration_ratio:,
          rate_phase_code: cycle.phase.code
        )
      end
    end
  end
end
