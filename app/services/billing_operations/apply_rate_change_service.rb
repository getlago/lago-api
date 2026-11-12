# frozen_string_literal: true

module BillingOperations
  # Applies rate changes to existing fixed-billing chains whose coverage overlaps the effective date.
  # Activation and periodic continuation remain responsible for creating new cycles.
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

      # A failed replacement must roll back its cancellation even inside a caller's transaction.
      ActiveRecord::Base.transaction(requires_new: true) do
        # Re-read under the same lock as processing and termination before changing obligations.
        Customers::LockService.call!(customer:, scope: :billing_schedule) do
          rate = RateCardRate.find_by(id: rate_card_rate_id, organization_id: customer.organization_id)
          next unless rate && customer.reload.kept?
          next unless rate.rate_card.kept?

          contract_rate_cards = ContractRateCard.where(organization_id: customer.organization_id, rate_card_id: rate.rate_card_id)
            .joins(:contract).where(contracts: {customer_id: customer.id, status: :active})
            .includes(:rate_card, :terms, {rate_phases: :rate_override}, contract: :customer)
          contract_rate_cards.find_each { |contract_rate_card| apply_rate_change(contract_rate_card, rate) }

          if result.billing_operations.any? { it.due_for_processing?(timestamp: Time.current) }
            ProcessJob.perform_after_commit(customer.id)
          end
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

    def apply_rate_change(contract_rate_card, rate)
      action_type = contract_rate_card.periodic_billing_action
      return unless action_type.in?(%w[renew_fixed_advance close_fixed_arrears])

      schedule = BuildScheduleService.call!(contract_rate_card:).schedule
      cycle = schedule.cycle_at(rate.effective_from)
      # Changes at a cycle boundary are handled by normal periodic billing.
      return unless cycle && rate.effective_from > cycle.started_at

      operations = contract_rate_card.billing_operations.where(
        organization_id: customer.organization_id, target_cycle_started_at: cycle.started_at, cancelled_at: nil
      )
      if action_type == "renew_fixed_advance"
        reconcile_advance(contract_rate_card, rate, cycle, operations, action_type:)
      else
        replace_arrears_close(contract_rate_card, rate, cycle, schedule, operations, action_type:)
      end
    end

    # Purchased advance coverage keeps its price. Record a no-charge reconciliation while
    # leaving the renewal chain intact; reuse it on retries, including after processing.
    def reconcile_advance(contract_rate_card, rate, cycle, operations, action_type:)
      return unless operations.where(action_type:).exists?

      reconciliation = operations.find_by(
        action_type: "reconcile_advance_coverage", causation_type: "rate_change", billing_at: rate.effective_from
      )
      reconciliation ||= CreateService.call!(
        contract_rate_card:, action_type: "reconcile_advance_coverage", causation_type: "rate_change",
        planned_operation: Schedule::PlannedOperation.new(cycle_started_at: cycle.started_at, billing_at: rate.effective_from)
      ).operation
      result.billing_operations << reconciliation
    end

    # Move the pending close to the earliest outstanding boundary. Its successful processing
    # creates the later close, keeping the remaining coverage in the same sequential chain.
    def replace_arrears_close(contract_rate_card, rate, cycle, schedule, operations, action_type:)
      closes = operations.where(action_type:)
      processed_until = closes.where.not(processed_at: nil).maximum(:billing_at)
      # A late job must not move a boundary into coverage that has already been billed.
      return if processed_until && processed_until >= rate.effective_from

      pending_close = closes.pending.order(:billing_at, :id).first
      return unless pending_close && pending_close.billing_at > rate.effective_from

      # Use all known rates so out-of-order jobs cannot skip an earlier outstanding slice.
      planned_operation = schedule.next_planned_operation(cycle, action_type:, after: processed_until)
      return unless planned_operation && planned_operation.billing_at < pending_close.billing_at

      pending_close.update!(cancelled_at: Time.current, cancelled_causation_type: "rate_change")
      result.billing_operations << CreateService.call!(
        contract_rate_card:, action_type:, causation_type: "rate_change", planned_operation:
      ).operation
    end
  end
end
