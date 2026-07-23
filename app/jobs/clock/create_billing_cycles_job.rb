# frozen_string_literal: true

module Clock
  # Producer scan as a batched, self-chaining job (same pattern as the DatabaseMigrations
  # backfill jobs): each run keyset-pages one BATCH_SIZE of DISTINCT customers with a due
  # item, fans out one ScheduleJob per customer, then re-enqueues itself for the next
  # page. The chain spreads the scan across small runs; the per-customer jobs run in
  # parallel. Deduped per customer downstream, so overlapping ticks don't double-schedule.
  class CreateBillingCyclesJob < ClockJob
    # Self-chaining, so a crashed head could otherwise hold the uniqueness lock and stall
    # the outbox forever; lock_ttl auto-expires it well within a few 5-minute ticks.
    unique :until_executed, on_conflict: :log, lock_ttl: 10.minutes

    BATCH_SIZE = 1_000

    def perform(cursor = nil)
      scope = SubscriptionRateCard.where("next_billing_at <= ?", Time.current).where(ended_at: nil)
      scope = scope.where("customer_id > ?", cursor) if cursor
      customer_ids = scope.order(:customer_id).distinct.limit(BATCH_SIZE).pluck(:customer_id)
      return if customer_ids.empty?

      customer_ids.each { |customer_id| BillingCycles::ScheduleJob.perform_later(customer_id) }
      self.class.perform_later(customer_ids.last)
    end
  end
end
