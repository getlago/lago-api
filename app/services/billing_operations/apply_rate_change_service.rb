# frozen_string_literal: true

module BillingOperations
  # Replans periodic billing and records the fixed-advance schedule at the rate change.
  class ApplyRateChangeService < BaseService
    Result = BaseResult

    def initialize(customer:, rate_card_rate_id:)
      @customer = customer
      @rate_card_rate_id = rate_card_rate_id
      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      # Re-read under the same lock and transaction as processing and termination.
      Customers::LockService.call!(customer:, scope: :billing_schedule) do
        # A deleted rate still names the card whose schedule changed.
        rate = RateCardRate.with_discarded.find_by(id: rate_card_rate_id, organization_id: customer.organization_id)
        next unless rate

        affected_contract_rate_cards(rate).find_each { apply_rate_change(it, rate) }
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
      ContractRateCard.starting_before_contract_end.where(organization_id: customer.organization_id, rate_card_id: rate.rate_card_id)
        .where(contracts: {customer_id: customer.id, status: Contract::BILLABLE_STATUSES, started_at: ..Time.current})
        .includes(rate_card: :rates, rate_phases: :rate_override, contract: :customer)
    end

    def apply_rate_change(contract_rate_card, rate)
      return unless contract_rate_card.periodic_billing_action

      next_billing_at = contract_rate_card.next_billing_at
      reconcile = contract_rate_card.needs_reconciliation?
      earlier_or_missing = next_billing_at.nil? || rate.effective_from < next_billing_at
      return unless earlier_or_missing || reconcile
      return if contract_rate_card.rate_card.rates.empty?

      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      # A postponed rate can displace a future renewal, but overdue work must stay due.
      if earlier_or_missing || (next_billing_at.future? && schedule.obligation_at(next_billing_at)&.billing_at != next_billing_at)
        ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, schedule:)
      end
      return unless reconcile

      # Jobs carry only the rate ID: edits before execution share the version the worker reads.
      operation_id = Digest::UUID.uuid_v5(contract_rate_card.id, rate.cache_key_with_version)
      return if contract_rate_card.billing_operations.exists?(id: operation_id, organization_id: customer.organization_id)

      # Use the date from before the reset: its coverage may have been extended by the edit.
      obligation = schedule.reconciliation_obligation(effective_from: rate.effective_from, next_billing_at:)
      plan = Schedule::PlannedOperation.from_obligation(obligation)
      return unless plan

      CreateService.call!(contract_rate_card:, action_type: "reconcile_advance_coverage", reason: "rate_change",
        planned_operation: plan, operation_id:)
    end
  end
end
