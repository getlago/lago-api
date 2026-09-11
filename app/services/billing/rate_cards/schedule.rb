# frozen_string_literal: true

module Billing
  module RateCards
    class Schedule
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
      def segments_due_by(timestamp, billing_from: nil)
        cycles = walker.walk_to(timestamp, from: resume_at)

        cycles.flat_map do |cycle|
          segments = billable_segments_of([cycle])

          if billing_from
            # A saved arrears clock can point to the original cycle end even
            # after termination shortens it. Select against the unshortened
            # pricing windows, then persist the actual service boundaries.
            full_cycle = cycle.with(ended_at: cycle.calendar.interval_containing(cycle.started_at).end)
            eligible_starts = billable_segments_of([full_cycle]).filter_map do |segment|
              if segment.billing_at >= billing_from || (segment.started_at...segment.ended_at).cover?(billing_from)
                segment.started_at
              end
            end
            segments = segments.select { eligible_starts.include?(it.started_at) }
          end

          segments.select { it.billing_at <= timestamp }
        end
      end

      # Next billing instant strictly after the given time, or nil when billing has ended.
      def next_billing_at(after:)
        cycle = walker.resume(after)

        while cycle
          segment = billable_segments_of([cycle]).find do |candidate|
            candidate.billing_at > after
          end

          if segment
            return segment.billing_at
          end

          cycle = walker.advance
        end

        nil
      end

      # Bill the segment being served, or the first future one if pricing has not started.
      def billing_at_covering(timestamp)
        segment = segment_at(timestamp)

        segment&.billing_at || next_billing_at(after: timestamp)
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

      attr_reader :rates, :terms, :timezone, :resume_at, :walker

      def segment_at(timestamp)
        cycle = walker.resume(timestamp)

        if cycle
          billable_segments_of([cycle]).find do |segment|
            (segment.started_at...segment.ended_at).cover?(timestamp)
          end
        end
      end

      def billable_segments_of(cycles)
        cycles.flat_map do |cycle|
          Segments.within(cycle, rates:).filter_map do |segment|
            if segment.rate
              build_billable_segment(cycle:, segment:)
            end
          end
        end
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
