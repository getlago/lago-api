# frozen_string_literal: true

module Clock
  class ProcessBillingSegmentsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      pending_customer_ids.each { |customer_id| BillingSegments::ProcessJob.perform_later(customer_id) }
    end

    private

    def pending_customer_ids
      BillingSegment.awaiting_invoicing
        .joins(:customer)
        .where(customers: {deleted_at: nil})
        .distinct
        .pluck(:customer_id)
    end
  end
end
