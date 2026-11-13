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
            operation = schedule_card(contract_rate_card)
            scheduled_operations << operation if operation
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
      return unless action_type

      previous_operation = contract_rate_card.billing_operations.periodic.completed
        .where(organization_id: customer.organization_id, action_type:, cancelled_at: nil)
        .order(billing_at: :desc, created_at: :desc, id: :desc)
        .first
      cycle_started_at = previous_operation&.target_cycle_started_at ||
        contract_rate_card.effective_date.in_time_zone(customer.applicable_timezone)
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      planning = if previous_operation
        {after: previous_operation.billing_at, from: cycle_started_at}
      else
        {at: cycle_started_at}
      end
      planned_operation = Schedule::BuildPlannedOperation.call!(contract_rate_card:, schedule:, **planning).planned_operation
      return unless planned_operation && planned_operation.billing_at <= timestamp

      existing_operation = contract_rate_card.billing_operations.periodic.pending.exists?(
        organization_id: customer.organization_id, action_type:, billing_at: planned_operation.billing_at,
        target_cycle_started_at: planned_operation.cycle_started_at
      )
      return if existing_operation

      CreateService.call!(
        contract_rate_card:, action_type:, causation_type: "periodic_continuation", planned_operation:
      ).operation
    end
  end
end
