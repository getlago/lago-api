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
        ApplicationRecord.transaction(requires_new: true) do
          ContractRateCard.due_for_billing(timestamp)
            .where(organization_id: customer.organization_id, contracts: {organization_id: customer.organization_id, customer_id: customer.id})
            .preload(rate_card: [:rates, {product: :billable_metric}], rate_phases: :rate_override, contract: :customer)
            .preload(:latest_completed_periodic_operation, :earliest_pending_periodic_operation)
            .find_in_batches do |cards|
              previous = BillingOperation.latest_periodic_by_card(cards, organization_id: customer.organization_id, through: timestamp)
              cards.each { |card| scheduled_operations.concat(schedule_card(card, previous[card.id])) }
          end
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

    def schedule_card(contract_rate_card, previous_operation)
      schedule = ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, timestamp:).schedule
      return [] unless schedule

      Schedule::DueOperationsService.call!(contract_rate_card:, schedule:, timestamp:, previous_operation:).billing_operations
    end
  end
end
