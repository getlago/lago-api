# frozen_string_literal: true

module Billing
  module RateCards
    class Schedule
      BILLING_TARGET = {current: "current", next: "next"}.freeze

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

      def billable_segments_for_cycle(cycle)
        billable_segments_of([cycle])
      end

      def next_billable_cycle(after_cycle_started_at:)
        cycle = walker.resume(after_cycle_started_at)
        cycle = walker.cycle_after(cycle) while cycle && cycle.started_at <= after_cycle_started_at

        while cycle
          return cycle if priced_segments_for_cycle(cycle).any?

          cycle = walker.cycle_after(cycle)
        end

        nil
      end

      # The current billing instant covers the time being served; the next is strictly later.
      def billing_at(timestamp:, target:)
        raise ArgumentError, "unknown billing target: #{target}" unless BILLING_TARGET.value?(target)

        if target == BILLING_TARGET.fetch(:current)
          segment = segment_covering(timestamp)
          segment&.billing_at || find_billing_after(timestamp)
        else
          find_billing_after(timestamp)
        end
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

      attr_reader :rates, :terms, :timezone, :resume_at, :walker

      def find_billing_after(timestamp)
        cycle = walker.resume(timestamp)

        while cycle
          segment = billable_segments_of([cycle]).find do |candidate|
            candidate.billing_at > timestamp
          end

          if segment
            return segment.billing_at
          end

          cycle = walker.cycle_after(cycle)
        end

        nil
      end

      def billable_segments_of(cycles)
        cycles.flat_map do |cycle|
          segments = priced_segments_for_cycle(cycle)
          next [] if segments.empty?

          segments.map { build_billable_segment(cycle:, segment: it) }
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
