# frozen_string_literal: true

module Billing
  module RateCards
    class Schedule
      attr_reader :resume_at

      def initialize(rates:, terms:, phases:, starts_at:, anchor_date:, timezone:, ends_at: nil, resume_at: nil)
        if resume_at && resume_at < starts_at.in_time_zone(timezone).beginning_of_day
          raise ArgumentError, "resume_at #{resume_at} precedes the card's start"
        end

        @rates = rates
        @terms = terms
        @timezone = timezone
        @resume_at = resume_at
        @walker = CycleWalker.new(rates:, phases:, starts_at:, anchor_date:, timezone:, ends_at:)
      end

      # A rate change can make a segment due before its cycle ends.
      def segments_due_by(timestamp)
        cycles = walker.walk_to(timestamp, from: resume_at)

        billable_segments_of(cycles).select do |segment|
          segment.billing_at <= timestamp
        end
      end

      def cycle_at(timestamp)
        walker.resume(timestamp)
      end

      # Every priced slice in billing order, from the cycle containing `from`.
      # Unpriced cycles yield nothing.
      def segments(from: resume_at)
        Enumerator.new do |yielder|
          cycle = walker.resume(from)

          while cycle
            billable_segments_of([cycle]).each { yielder << it }
            cycle = walker.cycle_after(cycle)
          end
        end.lazy
      end

      # The first slice still open at the instant, or falling due exactly on it.
      # A block maps a slice to its due instant when the caller's differs from the terms'.
      def first_obligation(at:, from: at)
        segments(from:).find { it.ended_at > at || (block_given? ? yield(it) : it.billing_at) == at }
      end

      # The first slice falling due strictly after a completed billing instant.
      def next_obligation(after:, from: after)
        segments(from:).find { (block_given? ? yield(it) : it.billing_at) > after }
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

      # Measure consumption against the original billed segment, whose end is exclusive.
      def consumed_ratio(segment:, at:)
        segment_days = Days.between(segment.started_at, segment.ended_at, timezone:)

        if segment_days.zero?
          1.0
        else
          consumed_until = at.clamp(segment.started_at, segment.ended_at)
          consumed_days = Days.between(segment.started_at, consumed_until, timezone:)

          consumed_days.fdiv(segment_days)
        end
      end

      private

      attr_reader :rates, :terms, :timezone, :walker

      def billable_segments_of(cycles)
        cycles.flat_map do |cycle|
          priced_segments_for_cycle(cycle).map { build_billable_segment(cycle:, segment: it) }
        end
      end

      def priced_segments_for_cycle(cycle)
        Segments.within(cycle, rates:).select(&:rate)
      end

      def build_billable_segment(cycle:, segment:)
        proration_ratio = if terms.prorated
          cycle.calendar.proration_ratio(segment.started_at, segment.ended_at)
        else
          1.0
        end

        BillableSegment.new(
          cycle_index: cycle.index,
          cycle_started_at: cycle.started_at,
          started_at: segment.started_at,
          ended_at: segment.ended_at,
          billing_at: terms.billing_at_for(segment),
          rate: segment.rate,
          rate_override: cycle.phase.rate_override,
          proration_ratio:,
          rate_phase_code: cycle.phase.code
        )
      end
    end
  end
end
