# frozen_string_literal: true

module BillingOperations
  # Under the caller's customer billing-schedule lock, preserves owed work and persists all
  # missing obligations through the effective end. ProcessService invoices them when due.
  class ApplyTerminationService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(contract:, timestamp:)
      @contract = contract
      @timestamp = timestamp
      super
    end

    def call
      result.billing_operations = []
      cancel_pending_operations

      final_cards.find_each do |card|
        create_missing_operations(card)
      end

      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contract, :timestamp

    # A later termination must not extend service beyond the contract's natural end.
    def effective_contract_end
      [contract.ended_at, contract.terminated_at].compact.min || timestamp
    end

    # Keep overdue work for retry, including a close due exactly at termination. A cycle
    # starting at the exclusive contract end owes nothing, even if its renewal is already due.
    def cancel_pending_operations
      card_ids = ContractRateCard.with_discarded
        .where(organization_id: contract.organization_id, contract_id: contract.id)
        .select(:id)

      BillingOperation.pending
        .where(organization_id: contract.organization_id, contract_rate_card_id: card_ids)
        .where("billing_at > :timestamp OR target_cycle_started_at >= :contract_end",
          timestamp:, contract_end: effective_contract_end)
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

    # Termination takes over the periodic chain: a future end needs every intervening cycle,
    # not just the final one. New obligations carry contract_termination and have no successor.
    def create_missing_operations(card)
      action_type = card.periodic_billing_action
      return unless action_type

      schedule = BuildScheduleService.call!(contract_rate_card: card, ends_at: effective_contract_end).schedule
      # Pending work reserves coverage even after failure; processed work must not be billed
      # again. For each cycle, only slices beyond its latest live boundary need new operations.
      covered_until = card.billing_operations
        .where(organization_id: contract.organization_id, action_type:, cancelled_at: nil)
        .group(:target_cycle_started_at).maximum(:billing_at)

      schedule.segments_due_by(timestamp).group_by(&:cycle_started_at).each do |cycle_started_at, segments|
        segments.map { schedule.due_at(it, action_type:) }.uniq.sort.each do |due_at|
          next if covered_until[cycle_started_at] && due_at <= covered_until[cycle_started_at]

          # Preserve intermediate due dates; the final close uses the termination timestamp,
          # which can be later than the natural end of service.
          billing_at = (due_at == effective_contract_end) ? timestamp : due_at
          planned_operation = Schedule::PlannedOperation.new(cycle_started_at:, billing_at:)
          result.billing_operations << CreateService.call!(
            contract_rate_card: card, action_type:, causation_type: "contract_termination", planned_operation:
          ).operation
        end
      end
    end
  end
end
