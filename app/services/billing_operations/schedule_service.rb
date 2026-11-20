# frozen_string_literal: true

module BillingOperations
  class ScheduleService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(customer:, timestamp: Time.current)
      @customer = customer
      @timestamp = timestamp
      super
    end

    def call
      result.billing_operations = []
      return result.not_found_failure!(resource: "customer") unless customer

      scheduled_operations = []
      Customers::LockService.call!(customer:, scope: :billing_schedule) do
        ContractRateCard.due_for_billing(timestamp)
          .where(organization_id: customer.organization_id, contracts: {organization_id: customer.organization_id, customer_id: customer.id})
          .includes(rate_card: [:rates, {product: :billable_metric}], rate_phases: :rate_override, contract: :customer)
          .find_each do |contract_rate_card|
            scheduled_operations.concat(schedule_card(contract_rate_card))
        end
      end
      result.billing_operations = scheduled_operations
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :customer, :timestamp

    def schedule_card(contract_rate_card)
      action_type = contract_rate_card.periodic_billing_action
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule if action_type
      # The reset moves the clock to the next obligation, or clears it when there is none.
      ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, schedule:)
      return [] unless schedule && action_type

      obligation = schedule.next_obligation(from: timestamp, after: timestamp)
      next_planned_operation = Schedule::PlannedOperation.from_obligation(obligation, after: timestamp)
      Schedule::DueOperationsService.call!(contract_rate_card:, next_planned_operation:, schedule:, timestamp:).billing_operations
    end
  end
end
