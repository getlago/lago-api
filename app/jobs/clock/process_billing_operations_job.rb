# frozen_string_literal: true

module Clock
  class ProcessBillingOperationsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      due_customer_ids.each { |customer_id| BillingOperations::ProcessJob.perform_later(customer_id) }
    end

    private

    def due_customer_ids
      timestamp = Time.current
      due = BillingOperation.due_for_processing(timestamp).where(action_type: BillingOperation::PERIODIC_ACTIONS.keys)

      Customer.joins(contracts: {applied_rate_cards: :billing_operations}).merge(due)
        .where(contracts: {status: %w[active terminated], started_at: ..timestamp})
        .where("contracts.organization_id = customers.organization_id AND contract_rate_cards.organization_id = customers.organization_id")
        .where("billing_operations.organization_id = customers.organization_id AND billing_operations.customer_id = customers.id")
        .distinct.order(:id).ids
    end
  end
end
