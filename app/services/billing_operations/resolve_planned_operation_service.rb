# frozen_string_literal: true

module BillingOperations
  # Resolves an operation against its target cycle and due date.
  class ResolvePlannedOperationService < BaseService
    Result = BaseResult[:planned_operation, :next_planned_operation]

    def initialize(operation:, schedule:)
      @operation = operation
      @schedule = schedule
      super
    end

    def call
      return result unless action_type

      cycle = schedule.cycle_at(target_cycle_started_at)
      return result unless cycle

      planned_operations = schedule.planned_operations_for_cycle(cycle, action_type:)
      planned_operation = if operation.causation_type == "contract_termination"
        planned_operations.last
      else
        planned_operations.find { it.billing_at == operation.billing_at }
      end

      result.planned_operation = planned_operation
      if planned_operation && operation.causation_type != "contract_termination"
        result.next_planned_operation = schedule.next_planned_operation(planned_operation:, action_type:)
      end
      result
    end

    private

    attr_reader :operation, :schedule

    delegate :action_type, :target_cycle_started_at, to: :operation, private: true
  end
end
