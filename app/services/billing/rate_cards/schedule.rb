# frozen_string_literal: true

module Billing
  module RateCards
    # Answers when a rate card bills its priced slices, grouped by cycle or by segment.
    class Schedule
      def initialize(
        rates:, terms:, phases:, starts_at:, anchor_date:, timezone:,
        ends_at: nil
      )
        @rates = rates
        @terms = terms
        @walker = CycleWalker.new(rates:, phases:, starts_at:, anchor_date:, timezone:, ends_at:)
      end

      # The cycle containing the instant, or nil once the schedule has ended.
      def cycle_at(timestamp)
        walker.resume(timestamp)
      end

      # Only the cycle containing the instant is searched backwards.
      def first_obligation(at:)
        obligations(from: at).find { it.segments.last.ended_at > at || it.billing_at == at }
      end

      # `from` names the target cycle when billing belongs to an earlier cycle than its instant.
      # A block maps an obligation to its adjusted billing instant.
      def next_obligation(after:, from: after)
        obligations(from:).find { (block_given? ? yield(it) : it.billing_at) > after }
      end

      # The slices of one cycle falling due after a completed billing and by the given instant:
      # what one operation of that cycle bills. `cycle_started_at` must be a cycle's own start.
      def segments_due_in_cycle(cycle_started_at, by:, after: nil)
        cycle = walker.resume(cycle_started_at)
        return [] unless cycle && cycle.started_at == cycle_started_at

        obligations_for(cycle)
          .select { (after.nil? || it.billing_at > after) && it.billing_at <= by }
          .flat_map(&:segments)
      end

      # Find the priced slice serving this instant, independently of completed operations.
      def segment_covering(timestamp)
        cycle = walker.resume(timestamp)

        if cycle
          obligations_for(cycle).flat_map(&:segments).find do |segment|
            (segment.started_at...segment.ended_at).cover?(timestamp)
          end
        end
      end

      private

      attr_reader :rates, :terms, :walker

      # Open-ended cards have no last cycle; unpriced cycles yield nothing.
      def obligations(from:)
        Enumerator.new do |yielder|
          cycle = walker.resume(from)

          while cycle
            obligations_for(cycle).each { yielder << it }
            cycle = walker.cycle_after(cycle)
          end
        end.lazy
      end

      def obligations_for(cycle)
        priced = priced_segments_for_cycle(cycle)
        return [] if priced.empty?

        groups = terms.cycle_scope? ? [priced] : priced.map { [it] }
        groups.map do |group|
          billing_at = terms.obligation_billing_at_for(cycle:, segments: group)
          segments = group.map { build_billable_segment(cycle:, segment: it, billing_at:) }
          Obligation.new(cycle:, segments:, billing_at:)
        end
      end

      def priced_segments_for_cycle(cycle)
        Segments.within(cycle, rates:).select(&:rate)
      end

      def build_billable_segment(cycle:, segment:, billing_at:)
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
          billing_at:,
          rate: segment.rate,
          rate_override: cycle.phase.rate_override,
          proration_ratio:,
          rate_phase_code: cycle.phase.code
        )
      end
    end
  end
end
