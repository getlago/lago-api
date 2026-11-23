# frozen_string_literal: true

module BillingOperations
  module Schedule
    # `cycle_started_at` identifies the cycle the operation bills. `billing_at` is when the
    # operation runs: the obligation's periodic billing instant (see Billing::Obligation).
    PlannedOperation = Data.define(:cycle_started_at, :billing_at, :coverage_started_at, :coverage_ended_at) do
      def self.from_obligation(obligation, after: nil)
        if obligation
          new(
            cycle_started_at: obligation.cycle.started_at,
            billing_at: obligation.operation_billing_at(after:),
            coverage_started_at: obligation.segments.first.started_at,
            coverage_ended_at: obligation.segments.last.ended_at
          )
        end
      end
    end
  end
end
