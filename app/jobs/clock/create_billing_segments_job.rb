# frozen_string_literal: true

module Clock
  class CreateBillingSegmentsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 10.minutes

    BATCH_SIZE = 1_000

    def perform(cursor = nil)
      scope = ContractRateCard.due_for_billing(Time.current)
      if cursor
        scope = scope.where("contracts.customer_id > ?", cursor)
      end

      customer_ids = scope.order("contracts.customer_id").distinct.limit(BATCH_SIZE).pluck("contracts.customer_id")
      customer_ids.each { |customer_id| BillingSegments::ScheduleJob.perform_later(customer_id) }

      if customer_ids.size == BATCH_SIZE
        self.class.perform_later(customer_ids.last)
      end
    end
  end
end
