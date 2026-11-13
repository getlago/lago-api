# frozen_string_literal: true

module BillingOperations
  # Creates one card's initial billing obligation as a durable operation.
  class CreateInitialOperationService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(contract_rate_card:, causation_type:)
      @contract_rate_card = contract_rate_card
      @causation_type = causation_type
      super
    end

    def call
      result.billing_operations = [initial_operation].compact
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract_rate_card, :causation_type

    def initial_operation
      pending_operation = contract_rate_card.billing_operations.pending.order(:billing_at, :id).first
      return pending_operation if pending_operation
      return if contract_rate_card.billing_operations.exists?

      schedule = BuildScheduleService.call!(
        contract_rate_card:
      ).schedule
      action = contract_rate_card.periodic_billing_action
      return unless action

      timezone = contract_rate_card.contract.customer.applicable_timezone
      cycle = schedule.next_billable_cycle(after_cycle_started_at: contract_rate_card.effective_date.in_time_zone(timezone).beginning_of_day - 1.second)
      return unless cycle

      planned_operation = schedule.next_planned_operation(cycle, action_type: action)

      BillingOperations::CreateService.call!(contract_rate_card:, action_type: action, causation_type:, planned_operation:).operation
    end
  end
end
