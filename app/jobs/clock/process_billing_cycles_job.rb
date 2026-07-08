# frozen_string_literal: true

module Clock
  # Consumer scan as a batched, self-chaining job: each run keyset-pages one BATCH_SIZE of
  # DISTINCT customers that have pending cycles, fans out one ProcessJob per customer, then
  # re-enqueues itself for the next page. Each ProcessJob groups that customer's WHOLE
  # pending set into invoices. Decoupled from production; a failed cycle stays pending and
  # is retried on the next scan.
  class ProcessBillingCyclesJob < ClockJob
    # Self-chaining, so a crashed head could otherwise hold the uniqueness lock and stall
    # the outbox forever; lock_ttl auto-expires it well within a few 5-minute ticks.
    unique :until_executed, on_conflict: :log, lock_ttl: 10.minutes

    BATCH_SIZE = 1_000

    def perform(cursor = nil)
      scope = BillingCycle.pending
      scope = scope.where("customer_id > ?", cursor) if cursor
      customer_ids = scope.order(:customer_id).distinct.limit(BATCH_SIZE).pluck(:customer_id)
      return if customer_ids.empty?

      customer_ids.each { |customer_id| BillingCycles::ProcessJob.perform_later(customer_id) }
      self.class.perform_later(customer_ids.last)
    end
  end
end
