# frozen_string_literal: true

module ContractRateCards
  class AdvanceBillingClockService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(operation:, resolution:)
      @operation = operation
      @resolution = resolution
      super
    end

    def call
      return result if operation.cancelled_at.present?
      action = operation.action_type
      return result unless BillingOperation::PERIODIC_ACTIONS.key?(action)
      return result if operation.action_type == "regroup_paid_fees" && operation.causation_type == "late_payment"

      contract_rate_card = operation.contract_rate_card
      next_planned_operation = resolution.schedule.next_planned_operation(
        resolution.cycle, action_type: action, after: operation.billing_at
      )
      contract_rate_card.update!(next_billing_at: next_planned_operation&.billing_at)
      result.contract_rate_card = contract_rate_card
      result
    end

    private

    attr_reader :operation, :resolution
  end
end
