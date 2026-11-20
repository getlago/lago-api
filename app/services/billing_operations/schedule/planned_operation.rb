# frozen_string_literal: true

module BillingOperations
  module Schedule
    # `cycle_started_at` identifies the cycle the operation bills. `billing_at` is when the
    # operation runs: the obligation's periodic billing instant (see Billing::Obligation).
    PlannedOperation = Data.define(:cycle_started_at, :billing_at) do
      def self.from_obligation(obligation, after: nil)
        if obligation
          new(cycle_started_at: obligation.cycle.started_at, billing_at: obligation.operation_billing_at(after:))
        end
      end

      def due_by?(timestamp, before: nil)
        billing_at <= timestamp && (before.nil? || billing_at < before)
      end
    end
  end
end
