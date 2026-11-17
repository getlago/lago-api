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

      # Select by coverage, not by the instant the obligation falls due.
      def obligation_at(timestamp)
        cycle = walker.resume(timestamp)
        return unless cycle && (cycle.started_at...cycle.ended_at).cover?(timestamp)

        obligations_for(cycle).find do |obligation|
          obligation.segments.any? { (it.started_at...it.ended_at).cover?(timestamp) }
        end
      end

      # Delayed operations can own several natural obligations, but never another cycle.
      def resolve_obligation(cycle_started_at:, billing_at:, after: nil)
        cycle = walker.resume(cycle_started_at)
        return unless cycle&.started_at == cycle_started_at

        segments = obligations_for(cycle)
          .select { it.billing_at <= billing_at && (after.nil? || it.billing_at > after) }
          .flat_map(&:segments)
          .map { it.with(billing_at:) }
        return if segments.empty?

        Obligation.new(cycle:, segments:, billing_at:)
      end

      # `from` names the target cycle when billing belongs to an earlier cycle than its instant.
      # A block maps an obligation to its adjusted billing instant.
      def next_obligation(from:, after: nil)
        obligations(from:).find do |obligation|
          if after.nil?
            obligation.segments.last.ended_at > from || obligation.billing_at == from
          else
            (block_given? ? yield(obligation) : obligation.billing_at) > after
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
        priced = Segments.within(cycle, rates:).select(&:rate)
        return [] if priced.empty?

        groups = terms.cycle_scope? ? [priced] : priced.zip
        groups.map do |group|
          billing_at = terms.obligation_billing_at_for(cycle:, segments: group)
          segments = group.map { build_billable_segment(cycle:, segment: it, billing_at:) }
          Obligation.new(cycle:, segments:, billing_at:)
        end
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
