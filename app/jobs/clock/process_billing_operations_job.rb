# frozen_string_literal: true

module Clock
  class ProcessBillingOperationsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      due_customer_ids.each { |customer_id| BillingOperations::ProcessJob.perform_later(customer_id) }
    end

    private

    def due_customer_ids
      ContractRateCard.due_for_billing(Time.current)
        .joins(contract: :customer).where(customers: {deleted_at: nil}).distinct.pluck("contracts.customer_id")
    end
  end
end
