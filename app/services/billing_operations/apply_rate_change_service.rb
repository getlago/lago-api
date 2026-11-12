# frozen_string_literal: true

module BillingOperations
  # Replans periodic billing after rate changes and reconciles fixed-advance coverage.
  class ApplyRateChangeService < BaseService
    Result = BaseResult[:billing_operations]

    def initialize(customer:, rate_card_rate_id:)
      @customer = customer
      @rate_card_rate_id = rate_card_rate_id
      super
    end

    def call
      result.billing_operations = []
      return result.not_found_failure!(resource: "customer") unless customer

      # Re-read under the same lock and transaction as processing and termination.
      Customers::LockService.call!(customer:, scope: :billing_schedule) do
        rate = RateCardRate.find_by(id: rate_card_rate_id, organization_id: customer.organization_id)

        affected_contract_rate_cards(rate).find_each { apply_rate_change(it, rate) }
        ProcessJob.perform_after_commit(customer.id) if result.billing_operations.any?
      end
      result
    rescue ActiveRecord::RecordInvalid => error
      result.record_validation_failure!(record: error.record)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :customer, :rate_card_rate_id

    def affected_contract_rate_cards(rate)
      timestamp = Time.current

      ContractRateCard.starting_before_contract_end.where(organization_id: customer.organization_id, rate_card_id: rate.rate_card_id)
        .where(contracts: {customer_id: customer.id, status: Contract::BILLABLE_STATUSES, started_at: ..timestamp})
        .where(next_billing_at: timestamp..rate.effective_from)
        .includes(:rate_card, :terms, {rate_phases: :rate_override}, contract: :customer)
    end

    def apply_rate_change(contract_rate_card, rate)
      plan_result = Schedule::BuildPlannedOperation.call!(contract_rate_card:, timestamp: rate.effective_from)

      if contract_rate_card.needs_reconciliation?
        return unless plan_result.planned_operation

        reconciliation = CreateService.call!(
          contract_rate_card:,
          action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage),
          causation_type: BillingOperation::CAUSATION_TYPES.fetch(:rate_change),
          planned_operation: plan_result.planned_operation
        )
        result.billing_operations << reconciliation.operation
      else
        timestamp = contract_rate_card.next_billing_at
        # Closing actions owe the cycle ending at the cursor, not at the new rate boundary.
        if contract_rate_card.periodic_billing_action.in?(ContractRateCard::TERMINATION_BILLING_ACTIONS)
          timestamp = BillingSegment.inclusive_end(timestamp)
        end

        ContractRateCards::ResetBillingClockService.call!(
          contract_rate_card:, timestamp:, schedule: plan_result.schedule
        )
      end
    end
  end
end
