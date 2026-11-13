# frozen_string_literal: true

module Clock
  # Fans out one scheduling job per customer with a due contract rate card.
  class ScheduleBillingOperationsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      due_customer_ids.each { |customer_id| BillingOperations::ScheduleJob.perform_later(customer_id) }
    end

    private

    def due_customer_ids
      ContractRateCard.due_for_billing(Time.current).distinct
        .order("contracts.customer_id").pluck("contracts.customer_id")
    end
  end
end
