# frozen_string_literal: true

module BillingOperations
  module Schedule
    # The obligation carries the cycle and coverage; `billing_at` is when the operation runs.
    PlannedOperation = Data.define(:obligation, :billing_at) do
      def self.from_obligation(obligation, after: nil)
        if obligation
          new(obligation:, billing_at: obligation.operation_billing_at(after:))
        end
      end

      def cycle_started_at = obligation.cycle.started_at

      def due_by?(timestamp, before: nil)
        billing_at <= timestamp && (before.nil? || billing_at < before)
      end
    end
  end
end
