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
        renewal_cancelled = cancel_pending_operations!(contract_rate_card)
        next if contract_rate_card.discarded?

        if contract_rate_card.requires_termination_billing?(timestamp:)
          operation = schedule_final_operation(contract_rate_card)
          billing_operations << operation if operation
        end
        # The termination can end coverage early. Replanning from the billing history keeps
        # overdue work and clears a clock with nothing left to bill, such as a later renewal.
        clock = ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, timestamp:)
        schedule_due_renewals(contract_rate_card, clock.schedule) if renewal_cancelled && clock.schedule
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

    def cancel_pending_operations!(contract_rate_card)
      due_renewal_cancelled = false
      contract_rate_card.billing_operations.to_cancel_on_termination(
        timestamp:, effective_end:, include_renewals: !contract_rate_card.discarded?
      ).find_each do |operation|
        operation.update!(
          cancelled_at: timestamp,
          cancellation_reason: BillingOperation::CANCELLATION_REASONS.fetch(:contract_termination)
        )
        due_renewal_cancelled ||= operation.billing_at <= timestamp
      end
      due_renewal_cancelled
    end

    def schedule_due_renewals(contract_rate_card, schedule)
      history = BillingOperation.latest_periodic_by_card([contract_rate_card], organization_id: contract.organization_id, through: timestamp)
      due = Schedule::DueOperationsService.call!(contract_rate_card:, schedule:, timestamp:, previous_operation: history[contract_rate_card.id])
      billing_operations.concat(due.billing_operations)
    end

    def schedule_final_operation(contract_rate_card)
      build = Billing::RateCards::BuildScheduleService.call(contract_rate_card:)
      return unless build.success?

      schedule = build.schedule
      planning_timestamp = BillingSegment.inclusive_end(effective_end)
      planned_operation = BillingOperations::Schedule::BuildPlannedOperation.call!(
        schedule:, at: planning_timestamp
      ).planned_operation
      return unless planned_operation

      planned_operation = planned_operation.with(billing_at: timestamp)
      return if final_operation_exists?(contract_rate_card, planned_operation)

      BillingOperations::CreateService.call!(
        contract_rate_card:,
        action_type: contract_rate_card.periodic_billing_action,
        reason: BillingOperation::REASONS.fetch(:contract_termination),
        planned_operation:
      ).operation
    end

    def effective_end
      [contract.billing_ends_at, timestamp].compact.min
    end

    def final_operation_exists?(contract_rate_card, planned_operation)
      contract_rate_card.billing_operations.where(
        action_type: contract_rate_card.periodic_billing_action,
        reason: BillingOperation::REASONS.fetch(:contract_termination),
        billing_at: timestamp,
        target_cycle_started_at: planned_operation.cycle_started_at,
        cancelled_at: nil
      ).exists?
    end
  end
end
