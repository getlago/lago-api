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

        affected_contract_rate_cards(rate).find_in_batches do |cards|
          sources = reconciliation_sources(cards, rate)
          cards.each { apply_rate_change(it, rate, sources.fetch(it.id, [])) }
        end
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
        .preload(:organization, rate_card: [:rates, {product: :billable_metric}], rate_phases: :rate_override, contract: :customer)
        .preload(:earliest_pending_periodic_operation, :latest_completed_periodic_operation)
    end

    def reconciliation_sources(cards, rate)
      card_ids = cards.select(&:needs_reconciliation?).map(&:id)
      BillingOperation.where(organization_id: customer.organization_id, contract_rate_card_id: card_ids)
        .reconciliation_sources(at: rate.updated_at).group_by(&:contract_rate_card_id)
    end

    def apply_rate_change(contract_rate_card, rate, sources)
      schedule = ContractRateCards::ResetBillingClockService.call!(contract_rate_card:).schedule
      record_reconciliation(contract_rate_card, rate, schedule, sources) if schedule && contract_rate_card.needs_reconciliation?
    end

    def record_reconciliation(contract_rate_card, rate, schedule, sources)
      sources = [contract_rate_card.latest_completed_periodic_operation, *sources].compact
      sources.map(&:target_cycle_started_at).uniq.each do |cycle_started_at|
        # Processing a source renewal does not change the identity of this cycle's rate edit.
        operation_id = Digest::UUID.uuid_v5(contract_rate_card.id, "#{cycle_started_at.iso8601(6)}/#{rate.cache_key_with_version}")
        next if contract_rate_card.billing_operations.exists?(id: operation_id, organization_id: customer.organization_id)

        obligation = BuildReconciliationObligationService.call!(schedule:, target_cycle_started_at: cycle_started_at).obligation
        next unless obligation

        CreateService.call!(contract_rate_card:, action_type: "reconcile_advance_coverage", reason: "rate_change",
          planned_operation: Schedule::PlannedOperation.from_obligation(obligation), operation_id:)
      end
    end
  end
end
