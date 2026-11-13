# frozen_string_literal: true

module BillingOperations
  # The caller holds the customer billing lock while future work is cancelled and final
  # termination obligations are persisted.
  class TerminateService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(contract:, timestamp:)
      @contract = contract
      @timestamp = timestamp
      @billing_operations = []
      super
    end

    def call
      contract.applied_rate_cards.with_discarded.includes(:rate_card, contract: :customer).find_each do |contract_rate_card|
        cancel_future_operations!(contract_rate_card)
        next if contract_rate_card.discarded?

        next unless contract_rate_card.requires_termination_billing?(timestamp:)

        operation = schedule_final_operation(contract_rate_card)
        billing_operations << operation if operation
      end
      result.billing_operations = billing_operations
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract, :timestamp, :billing_operations

    def cancel_future_operations!(contract_rate_card)
      contract_rate_card.billing_operations.pending.where("billing_at > ?", timestamp).find_each do |operation|
        operation.update!(
          cancelled_at: timestamp,
          cancelled_causation_type: BillingOperation::CANCELLED_CAUSATION_TYPES.fetch(:contract_termination)
        )
      end
    end

    def schedule_final_operation(contract_rate_card)
      build = Billing::RateCards::BuildScheduleService.call(contract_rate_card:)
      return unless build.success?

      schedule = build.schedule
      planning_timestamp = BillingSegment.inclusive_end(effective_end)
      plan_result = BillingOperations::Schedule::BuildPlannedOperation.call!(
        contract_rate_card:, schedule:, timestamp: planning_timestamp
      )
      planned_operation = plan_result.planned_operation
      return unless planned_operation

      planned_operation = planned_operation.with(billing_at: timestamp)
      return if final_operation_exists?(contract_rate_card, planned_operation)

      create_result = BillingOperations::CreateService.call!(
        contract_rate_card:,
        action_type: contract_rate_card.periodic_billing_action,
        causation_type: BillingOperation::CAUSATION_TYPES.fetch(:contract_termination),
        planned_operation:
      )
      ContractRateCards::ResetBillingClockService.call!(
        contract_rate_card:, timestamp: planning_timestamp, schedule:
      )
      create_result.operation
    end

    def effective_end
      [contract.billing_ends_at, timestamp].compact.min
    end

    def final_operation_exists?(contract_rate_card, planned_operation)
      contract_rate_card.billing_operations.where(
        action_type: contract_rate_card.periodic_billing_action,
        causation_type: BillingOperation::CAUSATION_TYPES.fetch(:contract_termination),
        billing_at: timestamp,
        target_cycle_started_at: planned_operation.cycle_started_at,
        cancelled_at: nil
      ).exists?
    end
  end
end
