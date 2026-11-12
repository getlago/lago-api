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
      return result unless operation.advances_billing_clock?

      contract_rate_card = operation.contract_rate_card
      plan_result = BillingOperations::Schedule::BuildPlannedOperation.call!(
        contract_rate_card:,
        schedule: resolution&.schedule,
        timestamp: resolution&.cycle&.started_at,
        after: operation.billing_at
      )
      contract_rate_card.update!(next_billing_at: plan_result.planned_operation&.billing_at)
      result.contract_rate_card = contract_rate_card
      result
    end

    private

    attr_reader :operation, :resolution
  end
end
