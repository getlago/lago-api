# frozen_string_literal: true

module BillingOperations
  module Schedule
    # Turns the schedule's next obligation into what a billing operation stores.
    class BuildPlannedOperation < BaseService
      Result = BaseResult[:planned_operation]

      # `cycle_started_at` identifies the cycle the operation bills. `billing_at` is when the
      # operation runs: the slice's periodic billing instant (see Billing::BillableSegment).
      PlannedOperation = Data.define(:segment, :billing_at) do
        delegate :cycle_started_at, to: :segment
      end

      # Two ways to plan, and exactly one must be given:
      # - `at:` when nothing was billed yet from that instant (activation, clock reset, rate
      #   change, termination): the first obligation still open at it.
      # - `after_operation:` once a billing completed: the first obligation falling due later,
      #   walking from its cycle because a billing can belong to an earlier cycle.
      def initialize(schedule:, at: nil, after_operation: nil)
        raise ArgumentError, "pass either at: or after_operation:" unless at.nil? ^ after_operation.nil?

        @schedule = schedule
        @at = at
        @after_operation = after_operation
        super
      end

      def call
        segment = if after_operation
          schedule.next_obligation(after: after_operation.billing_at, from: after_operation.target_cycle_started_at) { operation_billing_at(it) }
        else
          schedule.first_obligation(at:)
        end

        if segment
          result.planned_operation = PlannedOperation.new(
            segment:,
            billing_at: after_operation ? operation_billing_at(segment) : segment.billing_at
          )
        end
        result
      end

      private

      attr_reader :schedule, :at, :after_operation

      # Outstanding final coverage closes at termination. Coverage already billed at the
      # planned end must not become due again when termination happens later.
      def operation_billing_at(segment)
        contract = after_operation.contract_rate_card.contract

        if contract.terminated_at && segment.billing_at == contract.billing_ends_at && segment.billing_at > after_operation.billing_at
          contract.terminated_at
        else
          segment.billing_at
        end
      end
    end
  end
end
