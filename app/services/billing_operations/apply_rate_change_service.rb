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
        # A deleted rate still names the card whose schedule changed.
        rate = RateCardRate.with_discarded.find_by(id: rate_card_rate_id, organization_id: customer.organization_id)
        next unless rate

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

    # Replanning reads the billing history, not the rate's date, so every running card of the
    # rate card is replanned, including one with no clock until this rate priced it.
    def affected_contract_rate_cards(rate)
      ContractRateCard.starting_before_contract_end.where(organization_id: customer.organization_id, rate_card_id: rate.rate_card_id)
        .where(contracts: {customer_id: customer.id, status: Contract::BILLABLE_STATUSES, started_at: ..Time.current})
        .includes(:rate_card, :terms, {rate_phases: :rate_override}, contract: :customer)
    end

    def apply_rate_change(contract_rate_card, rate)
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule

      if contract_rate_card.needs_reconciliation?
        # Renewed advance coverage is reconciled, not replanned, until a price change can tell
        # what that coverage already paid for.
        return unless contract_rate_card.next_billing_at&.between?(Time.current, rate.effective_from)

        planned_operation = Schedule::BuildPlannedOperation.call!(
          schedule:, at: rate.effective_from
        ).planned_operation
        return unless planned_operation

        reconciliation = CreateService.call!(
          contract_rate_card:,
          action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage),
          reason: BillingOperation::REASONS.fetch(:rate_change),
          planned_operation:
        )
        result.billing_operations << reconciliation.operation
      else
        ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, schedule:)
      end
    end
  end
end
