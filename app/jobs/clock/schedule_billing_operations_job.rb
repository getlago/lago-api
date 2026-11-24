# frozen_string_literal: true

module Clock
  # Saved work can still be due after its card loses its last live rate.
  class ScheduleBillingOperationsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      due_customer_ids.each { |customer_id| BillingOperations::ScheduleJob.perform_later(customer_id) }
    end

    private

    def due_customer_ids
      timestamp = Time.current
      due_cards = ContractRateCard.due_for_billing(timestamp).distinct
        .order("contracts.customer_id").pluck("contracts.customer_id")
      due_cards | Customer.with_due_periodic_operations(timestamp).order(:id).ids
    end
  end
end
