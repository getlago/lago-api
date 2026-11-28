# frozen_string_literal: true

module Billing
  module RateCards
    # Answers when a rate card bills its priced slices, grouped by cycle or by segment.
    class Schedule
      def initialize(
        rates:, terms:, phases:, starts_at:, anchor_date:, timezone:,
        ends_at: nil, termination_billing_at: nil
      )
        @rates = rates
        @terms = terms
        @ends_at = ends_at
        # When to bill the final outstanding obligation, separately from when coverage ends.
        # Example: contract coverage ends Nov 10; termination happens Nov 15.
        # When continuing after earlier billing, the final operation bills on Nov 15,
        # but covers nothing beyond Nov 10.
        @termination_billing_at = termination_billing_at
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

        Obligation.new(cycle:, segments:, billing_at:, terms:, termination_billing_at: termination_date_for(billing_at))
      end

      # `from` names the target cycle when billing belongs to an earlier cycle than its instant.
      def next_obligation(from:, after: nil)
        obligations(from:).find { it.selectable_from?(from, after:) }
      end

      def obligations_due_by(timestamp, from:, after: nil)
        due = []
        obligations(from:).each do |obligation|
          billing_at = obligation.operation_billing_at(after: after || due.first&.billing_at)
          break if billing_at > timestamp

          due << obligation if obligation.selectable_from?(from, after:)
        end
        due
      end

      private

      attr_reader :rates, :terms, :walker, :ends_at, :termination_billing_at

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
          billing_at = terms.obligation_billing_at_for(cycle:, segments: group)
          Obligation.new(cycle:, segments: group, billing_at:, terms:, termination_billing_at: termination_date_for(billing_at))
        end
      end

      # Only the final natural billing date carries termination metadata; earlier closes stay unchanged.
      # Example: coverage ends Nov 10, but the contract is terminated Nov 15.
      # The final obligation keeps its Nov 10 billing_at and coverage end. If still outstanding
      # after a Nov 1 billing, Obligation#operation_billing_at projects its operation date to Nov 15.
      # Coverage already billed through Nov 10 must not become due again at termination.
      def termination_date_for(billing_at)
        termination_billing_at if ends_at && billing_at == ends_at
      end
    end
  end
end
