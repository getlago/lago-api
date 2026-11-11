# frozen_string_literal: true

module Clock
  class ProcessBillingOperationsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      pending_customer_ids.each { |customer_id| BillingOperations::ProcessJob.perform_later(customer_id) }
    end

    private

    def pending_customer_ids
      BillingOperation.pending
        .where(billing_at: ..Time.current).joins(:customer)
        .where(customers: {deleted_at: nil}).distinct.pluck(:customer_id)
    end
  end
end
