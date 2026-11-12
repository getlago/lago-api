# frozen_string_literal: true

module BillingOperations
  # Moves outstanding fixed-arrears cursors earlier and records independent advance
  # reconciliations. Purchased advance coverage and its renewal cursor stay unchanged.
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

      # A failure on one card rolls back all cursor changes and reconciliations for this customer.
      ActiveRecord::Base.transaction(requires_new: true) do
        # Re-read under the same lock as processing and termination before changing obligations.
        Customers::LockService.call!(customer:, scope: :billing_schedule) do
          rate = RateCardRate.find_by(id: rate_card_rate_id, organization_id: customer.organization_id)
          next unless rate&.rate_card&.kept?
          next unless customer.reload.kept?

          contract_rate_cards = active_contract_rate_cards(rate)
          contract_rate_cards.find_each { apply_rate_change(it, rate) }
          ProcessJob.perform_after_commit(customer.id) if contract_rate_cards.due_for_billing(Time.current).exists?
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

    def active_contract_rate_cards(rate)
      ContractRateCard.where(organization_id: customer.organization_id, rate_card_id: rate.rate_card_id)
        .joins(:contract).where(contracts: {customer_id: customer.id, status: :active})
        .includes(:rate_card, :terms, {rate_phases: :rate_override}, contract: :customer)
    end

    def apply_rate_change(contract_rate_card, rate)
      action_type = contract_rate_card.periodic_billing_action
      return unless action_type.in?(%w[renew_fixed_advance close_fixed_arrears])

      schedule = BuildScheduleService.call!(contract_rate_card:).schedule
      cycle = schedule.cycle_at(rate.effective_from)
      # Changes at a cycle boundary are handled by normal periodic billing.
      return unless cycle && rate.effective_from > cycle.started_at

      operations = contract_rate_card.billing_operations.where(target_cycle_started_at: cycle.started_at, cancelled_at: nil)
      if action_type == "renew_fixed_advance"
        reconcile_advance(contract_rate_card, rate, cycle, operations, action_type:)
      else
        reschedule_arrears(contract_rate_card, rate, cycle, operations, action_type:)
      end
    end

    # Purchased advance coverage keeps its price. Record a no-charge reconciliation while
    # leaving the renewal chain intact; reuse it on retries, including after processing.
    def reconcile_advance(contract_rate_card, rate, cycle, operations, action_type:)
      represented = (cycle.started_at...cycle.ended_at).cover?(contract_rate_card.next_billing_at)
      return unless represented || operations.completed.where(action_type:).exists?

      reconciliation = operations.find_by(
        action_type: "reconcile_advance_coverage", causation_type: "rate_change", billing_at: rate.effective_from
      )
      reconciliation ||= CreateReconciliationService.call!(
        contract_rate_card:, causation_type: "rate_change",
        planned_operation: Schedule::PlannedOperation.new(cycle_started_at: cycle.started_at, billing_at: rate.effective_from)
      ).operation
      result.billing_operations << reconciliation
    end

    # Earlier overdue work keeps its cursor; successful processing discovers later boundaries.
    def reschedule_arrears(contract_rate_card, rate, cycle, operations, action_type:)
      processed_until = operations.completed.where(action_type:).maximum(:billing_at)
      # A late job must not move a boundary into coverage that has already been billed.
      return if processed_until && processed_until >= rate.effective_from

      cursor = contract_rate_card.next_billing_at
      return unless cursor && cursor > rate.effective_from && cursor <= cycle.ended_at

      # Reset from the first unbilled instant, so out-of-order jobs cannot skip an earlier outstanding slice.
      ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, timestamp: processed_until || cycle.started_at)
    end
  end
end
