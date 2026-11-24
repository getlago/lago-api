# frozen_string_literal: true

module BillingOperations
  # Returns the revised obligation to reconcile against the last completed operation, or nil.
  # Use its saved coverage even if the scheduler has already advanced the card's billing date.
  class ReconciliationObligation
    def self.call(schedule:, previous:, rate:)
      return if previous.nil? || previous.segments.empty?

      # With segment billing, inserting B on Nov 15 inside completed A [Nov 1, Dec 1) selects B.
      # Dec 1 itself is outside that window: a B starting then leaves November A unchanged.
      coverage = previous.coverage_started_at...previous.coverage_ended_at
      revised = schedule.obligation_at(coverage.cover?(rate.effective_from) ? rate.effective_from : coverage.begin)
      return unless revised
      # If the revised obligation uses the edited rate, its dates need not change to qualify.
      return revised if revised.segments.any? { it.rate.id == rate.id }

      # Postponing B from Nov 15 to Nov 20 extends completed A [Nov 1, Nov 15) to [Nov 1, Nov 20).
      # Moving B to Dec 15 extends November A only to Dec 1. In both cases select A, not future B.
      saved = previous.segments.map { [it.started_at, it.ended_at, it.rate_card_rate_id] }
      current = revised.segments.map { [it.started_at, it.ended_at, it.rate.id] }
      revised if current != saved
    end
  end
end
