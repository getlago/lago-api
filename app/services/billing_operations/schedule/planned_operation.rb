# frozen_string_literal: true

module BillingOperations
  module Schedule
    # The operation can run on a different date without changing the obligation's coverage.
    PlannedOperation = Data.define(:obligation, :billing_at) do
      def self.from_obligation(obligation, after: nil)
        new(obligation:, billing_at: obligation.operation_billing_at(after:)) if obligation
      end

      def cycle_started_at = obligation.cycle.started_at

      delegate :coverage_started_at, to: :obligation

      def coverage_ended_at = obligation.segments.last.ended_at
    end
  end
end
