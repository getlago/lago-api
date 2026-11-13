# frozen_string_literal: true

module BillingOperations
  class EnsureNextService < BaseService
    Result = BaseResult[:operation]

    def initialize(operation:, resolution:)
      @operation = operation
      @resolution = resolution
      super
    end

    def call
      return result if operation.cancelled_at.present?
      return result if operation.causation_type == "contract_termination"

      action = operation.action_type
      return result unless BillingOperation::PERIODIC_ACTIONS.key?(action)
      return result if operation.action_type == "regroup_paid_fees" && operation.causation_type == "late_payment"

      contract_rate_card = operation.contract_rate_card
      # Termination has already persisted every remaining obligation through the contract end.
      return result if contract_rate_card.contract.terminated?
      return result unless resolution.cycle

      next_planned_operation = resolution.schedule.next_planned_operation(
        resolution.cycle, action_type: action, after: operation.billing_at
      )
      return result unless next_planned_operation

      result.operation = BillingOperations::CreateService.call!(
        contract_rate_card:, action_type: action, causation_type: "periodic_continuation",
        planned_operation: next_planned_operation
      ).operation
      result
    end

    private

    attr_reader :operation, :resolution
  end
end
