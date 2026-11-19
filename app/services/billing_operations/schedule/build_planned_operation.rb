# frozen_string_literal: true

module BillingOperations
  module Schedule
    # Turns the schedule's next obligation into what a billing operation stores.
    class BuildPlannedOperation < BaseService
      Result = BaseResult[:planned_operation]

      # Two ways to plan, and exactly one must be given:
      # - `at:` when nothing was billed yet from that instant (activation, clock reset, rate
      #   change, termination): the first obligation still open at it.
      # - `after_operation:` after a persisted operation: the first obligation falling due later,
      #   walking from its cycle because a billing can belong to an earlier cycle.
      def initialize(schedule:, at: nil, after_operation: nil)
        raise ArgumentError, "pass either at: or after_operation:" unless at.nil? ^ after_operation.nil?

        @schedule = schedule
        @at = at
        @after_operation = after_operation
        super
      end

      def call
        obligation = if after_operation
          schedule.next_obligation(from: after_operation.target_cycle_started_at, after: after_operation.billing_at)
        else
          schedule.next_obligation(from: at)
        end

        result.planned_operation = PlannedOperation.from_obligation(obligation, after: after_operation&.billing_at)
        result
      end

      private

      attr_reader :schedule, :at, :after_operation
    end
  end
end
