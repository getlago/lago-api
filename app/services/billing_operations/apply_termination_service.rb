# frozen_string_literal: true

module BillingOperations
  # Cancels pending work and creates the contract's final arrears or regroup operation.
  class ApplyTerminationService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(contract:, timestamp:)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      result.billing_operations = []
      # Earlier cycles are assumed processed; cancellation does not replay overdue obligations.
      cancel_pending_operations

      final_cards.find_each do |card|
        schedule = BuildScheduleService.call!(contract_rate_card: card).schedule
        planned_operation = final_planned_operation(card, schedule)
        next unless planned_operation
        next if final_operation_already_processed?(card, planned_operation, card.periodic_billing_action)

        result.billing_operations << BillingOperations::CreateService.call!(
          contract_rate_card: card,
          action_type: card.periodic_billing_action,
          causation_type: BillingOperation::CAUSATION_TYPES.fetch(:contract_termination),
          planned_operation: planned_operation.with(billing_at: timestamp)
        ).operation
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract, :timestamp

    def effective_contract_end
      [contract.ended_at, contract.terminated_at].compact.min || timestamp
    end

    def cancel_pending_operations
      card_ids = ContractRateCard.with_discarded
        .where(organization_id: contract.organization_id, contract_id: contract.id)
        .select(:id)

      BillingOperation.pending
        .where(organization_id: contract.organization_id, contract_rate_card_id: card_ids)
        .find_each do |operation|
          operation.update!(
            cancelled_at: timestamp,
            cancelled_causation_type: BillingOperation::CANCELLED_CAUSATION_TYPES.fetch(:contract_termination)
          )
        end
    end

    def final_cards
      ContractRateCard.priced.starting_before_contract_end
        .where(organization_id: contract.organization_id, contract_id: contract.id)
        .includes(:rate_card, {rate_phases: :rate_override}, contract: :customer)
    end

    def final_planned_operation(card, schedule)
      action_type = card.periodic_billing_action

      case action_type
      when BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance)
        # Fixed advance coverage was already billed; termination must not create another renewal.
        nil
      when BillingOperation::ACTION_TYPES.fetch(:renew_recurring_metered_advance)
        # Advance coverage was already billed; cancel renewals without another charge or refund.
        nil
      when BillingOperation::ACTION_TYPES.fetch(:close_fixed_arrears)
        # Close fixed arrears at termination for the final covered cycle.
        last_planned_operation(schedule, action_type)
      when BillingOperation::ACTION_TYPES.fetch(:close_metered_arrears)
        # Close accrued metered usage at termination for the final covered cycle.
        last_planned_operation(schedule, action_type)
      when BillingOperation::ACTION_TYPES.fetch(:regroup_paid_fees)
        # Group already-paid advance fees at termination without charging them again.
        last_planned_operation(schedule, action_type)
      end
    end

    def last_planned_operation(schedule, action_type)
      cycle = schedule.cycle_at(BillingSegment.inclusive_end(effective_contract_end))
      return unless cycle

      billing_at = schedule.billing_dates_for_cycle(cycle, action_type:).last
      return unless billing_at

      Schedule::PlannedOperation.new(cycle_started_at: cycle.started_at, billing_at:)
    end

    def final_operation_already_processed?(card, planned_operation, action_type)
      card.billing_operations
        .where(
          organization_id: contract.organization_id,
          action_type:,
          target_cycle_started_at: planned_operation.cycle_started_at
        )
        .where.not(processed_at: nil)
        .where(billing_at: planned_operation.billing_at..)
        .exists?
    end
  end
end
