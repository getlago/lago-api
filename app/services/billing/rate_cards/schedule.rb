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
          obligation.segments.any? { |segment| (segment.started_at...segment.ended_at).cover?(timestamp) }
        end
      end

      # Delayed operations can own several natural obligations, but never another cycle.
      def obligation_for_operation(cycle_started_at:, billing_at:, after: nil)
        cycle = walker.resume(cycle_started_at)
        return unless cycle&.started_at == cycle_started_at

        segments = obligations_for(cycle)
          .select { it.billing_at <= billing_at && (after.nil? || it.billing_at > after) }
          .flat_map(&:segments)
        return if segments.empty?

        Obligation.new(cycle:, segments:, billing_at:, terms:)
      end

      # `from` names the target cycle when billing belongs to an earlier cycle than its instant.
      # A block affects selection only; the returned obligation keeps its original billing_at.
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
        end
      end

      def obligations_for(cycle)
        priced = Segments.within(cycle, rates:).select(&:rate)
        return [] if priced.empty?

        groups = terms.cycle_scope? ? [priced] : priced.zip
        groups.map do |group|
          Obligation.new(cycle:, segments: group, billing_at: terms.obligation_billing_at_for(cycle:, segments: group), terms:)
        end
      end
    end
  end
end
