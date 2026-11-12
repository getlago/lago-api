# frozen_string_literal: true

module ContractRateCards
  # Starts the periodic cursor without persisting future billing history.
  class InitializeBillingClockService < BaseService
    Result = BaseResult[:contract_rate_card]

    def initialize(contract_rate_card:)
      @contract_rate_card = contract_rate_card
      super
    end

    def call
      result.contract_rate_card = contract_rate_card
      return result if contract_rate_card.next_billing_at || contract_rate_card.billing_operations.periodic.completed.exists?

      action = contract_rate_card.periodic_billing_action
      return result unless action && contract_rate_card.rate_card.rates.exists?

      schedule = BillingOperations::BuildScheduleService.call!(contract_rate_card:).schedule
      timezone = contract_rate_card.contract.customer.applicable_timezone
      cycle = schedule.next_billable_cycle(after_cycle_started_at: contract_rate_card.effective_date.in_time_zone(timezone).beginning_of_day - 1.second)
      planned_operation = schedule.next_planned_operation(cycle, action_type: action)
      contract_rate_card.update!(next_billing_at: planned_operation&.billing_at)
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract_rate_card
  end
end
