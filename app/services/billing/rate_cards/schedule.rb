# frozen_string_literal: true

module Billing
  module RateCards
    class Schedule
      # `due_on_coverage_end` makes every slice fall due when its coverage ends, whatever the terms' timing.
      def initialize(
        rates:, terms:, phases:, starts_at:, anchor_date:, timezone:,
        ends_at: nil, due_on_coverage_end: false
      )
        @rates = rates
        @terms = terms
        @due_on_coverage_end = due_on_coverage_end
        @walker = CycleWalker.new(rates:, phases:, starts_at:, anchor_date:, timezone:, ends_at:)
      end

      # A rate change can make a segment due before its cycle ends.
      def segments_due_by(timestamp)
        cycles = walker.walk_to(timestamp)

        billable_segments_of(cycles).select do |segment|
          segment.billing_at <= timestamp
        end
      end

      def cycle_at(timestamp)
        walker.resume(timestamp)
      end

      # The first slice still open at the instant, or falling due exactly on it.
      def first_obligation(at:)
        segments(from: at).find { it.ended_at > at || it.due_at == at }
      end

      # The first slice falling due strictly after a completed billing instant.
      # A block maps a slice to its due instant when the caller moves it.
      def next_obligation(after:, from: after)
        segments(from:).find { (block_given? ? yield(it) : it.due_at) > after }
      end

      # The slices of one cycle falling due after a completed billing and by the given instant.
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

      # Every priced slice in billing order, from the cycle containing `from`.
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
