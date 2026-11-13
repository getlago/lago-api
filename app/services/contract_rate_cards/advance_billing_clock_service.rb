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
      contract_rate_card.update!(next_billing_at: next_planned_operation&.billing_at)
      result.contract_rate_card = contract_rate_card
      result
    end

    private

    attr_reader :operation, :resolution

    # Nothing follows an operation whose cycle the schedule no longer has.
    def next_planned_operation
      cycle = resolution&.cycle
      return unless cycle

      BillingOperations::Schedule::BuildPlannedOperation.call!(
        contract_rate_card: operation.contract_rate_card,
        schedule: resolution.schedule,
        after: operation.billing_at,
        from: cycle.started_at
      ).planned_operation
    end
  end
end
