# frozen_string_literal: true

module BillingOperations
  module Schedule
    class BuildPlannedOperation < BaseService
      Result = BaseResult[:planned_operation]
      PlannedOperation = Data.define(:cycle_started_at, :billing_at)

      # Pass `at:` for the first obligation still open at an instant, or `after:` for the first
      # one falling due after a completed billing, walking from the cycle of `from:`.
      def initialize(contract_rate_card:, schedule:, at: nil, after: nil, from: nil)
        raise ArgumentError, "pass either at: or after:" unless at.nil? ^ after.nil?

        @contract_rate_card = contract_rate_card
        @schedule = schedule
        @at = at
        @after = after
        @from = from
        super
      end

      def call
        segment = if after
          schedule.next_obligation(after:, from:) { final_due_at(it) }
        else
          schedule.first_obligation(at:)
        end

        if segment
          result.planned_operation = PlannedOperation.new(
            cycle_started_at: segment.cycle_started_at,
            billing_at: after ? final_due_at(segment) : segment.due_at
          )
        end
        result
      end

      private

      attr_reader :contract_rate_card, :schedule, :at, :after, :from

      # A contract terminated after its planned end closes its last slice at the termination.
      def final_due_at(segment)
        contract = contract_rate_card.contract

        if contract.terminated_at && segment.due_at == contract.billing_ends_at
          contract.terminated_at
        else
          segment.due_at
        end
      end
    end
  end
end
