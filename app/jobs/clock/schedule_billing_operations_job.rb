# frozen_string_literal: true

module Clock
  # Schedules customers with periodic billing or pending units reconciliation.
  class ScheduleBillingOperationsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      due_customer_ids.each { |customer_id| BillingOperations::ScheduleJob.perform_later(customer_id) }
    end

    private

    def due_customer_ids
      periodic_customer_ids = ContractRateCard.due_for_billing(Time.current).distinct
        .order("contracts.customer_id").pluck("contracts.customer_id")
      reconciliation_customer_ids = BillingOperation.pending.units_changes
        .where(billing_at: ..Time.current)
        .joins(:customer, :contract_rate_card)
        .where(customers: {deleted_at: nil}, contract_rate_cards: {deleted_at: nil})
        .distinct.pluck(:customer_id)

      (periodic_customer_ids + reconciliation_customer_ids).uniq.sort
    end
  end
end
