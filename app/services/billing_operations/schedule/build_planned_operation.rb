# frozen_string_literal: true

module BillingOperations
  module Schedule
    # Turns the schedule's next obligation into what a billing operation stores.
    class BuildPlannedOperation < BaseService
      Result = BaseResult[:planned_operation]

      # `cycle_started_at` identifies the cycle the operation bills. `billing_at` is when the
      # operation runs: the slice's `due_at`, not its terms' `billing_at`, which differ for
      # cards that regroup paid advance fees (see Billing::BillableSegment).
      PlannedOperation = Data.define(:cycle_started_at, :billing_at)

      # Two ways to plan, and exactly one must be given:
      # - `at:` when nothing was billed yet from that instant (activation, clock reset, rate
      #   change, termination): the first obligation still open at it.
      # - `after:` once a billing completed: the first obligation falling due later, walking
      #   from the cycle of `from:` because a billing can belong to an earlier cycle.
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

      # A contract terminated after its planned end closes its last slice at the termination,
      # not at the planned end. Only applied after a completed billing, as the first plan of a
      # termination sets its own billing instant.
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
