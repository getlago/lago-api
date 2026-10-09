# frozen_string_literal: true

module Clock
  # Fans the producer out, one job per customer with a due card. A customer already queued or
  # running is dropped rather than queued again, and two that do overlap are made safe by the
  # lock and the transaction the per-customer run holds.
  class CreateBillingSegmentsJob < ClockJob
    # The tick is hourly and a run takes seconds. A shorter ttl than the tick means a
    # crashed run expires its lock before the next tick instead of costing one.
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    # One enqueue per due customer, in a single run. A normal tick has few; a first run or a
    # tick after an outage has as many as there are customers with a due card, measured at 65k
    # of 500k cards. Paging the scan and re-enqueueing itself is the way out if that ever hurts.
    def perform
      due_customer_ids.each { |customer_id| BillingSegments::ScheduleJob.perform_later(customer_id) }
    end

    private

    def due_customer_ids
      ContractRateCard.due_for_billing(Time.current).distinct.pluck(Arel.sql("contracts.customer_id"))
    end
  end
end
