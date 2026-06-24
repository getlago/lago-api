# frozen_string_literal: true

module Clock
  # Picks up every subscription product item whose clock is due and fans out a
  # ScheduleJob per item. The actual outbox work (create cycle + advance clock) lives
  # in the per-item job so the scan stays cheap. Scoped by the idx_spi_billable
  # partial index (next_billing_at where active).
  class CreateBillingCyclesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      SubscriptionProductItem
        .where("next_billing_at <= ?", Time.current)
        .where(ended_at: nil)
        .find_each do |subscription_product_item|
          BillingCycles::ScheduleJob.perform_later(subscription_product_item)
        end
    end
  end
end
