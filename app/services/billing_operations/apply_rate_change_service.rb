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
        # next_billing_at says when to bill next, not which coverage was already billed.
        # A Nov 15 rate change affects completed [Nov 1, Dec 1) coverage even with a Dec 1 cursor.
        return unless contract_rate_card.billing_operations.completed.periodic.where(
          organization_id: contract_rate_card.organization_id, cancelled_at: nil,
          action_type: BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance), coverage_started_at: ..rate.effective_from
        ).where("coverage_ended_at > ?", rate.effective_from).exists?

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
