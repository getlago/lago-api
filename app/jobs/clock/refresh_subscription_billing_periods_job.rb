# frozen_string_literal: true

module Clock
  # Rolls the periods of subscriptions whose current one has just ended. Keyset-pages a batch of
  # them, fans out one job each, then re-enqueues itself for the next page, so the scan is spread
  # over short runs instead of one job holding a connection for all of them.
  #
  # Costs one page per rollover rather than a walk over every active subscription, because the
  # periods themselves carry the index on period_to.
  class RefreshSubscriptionBillingPeriodsJob < ClockJob
    # Self-chaining, so a crashed head would hold the uniqueness lock and stall the sweep; the ttl
    # expires it well within a few ticks.
    unique :until_executed, on_conflict: :log, lock_ttl: 10.minutes

    BATCH_SIZE = 1_000

    def perform(cursor = nil)
      # Restricted to active subscriptions: the final period of a terminated one has no successor
      # to materialize, so it stays in `awaiting_rollover` for the whole window and would be
      # re-enqueued on every tick only for UpsertService to skip it.
      scope = SubscriptionBillingPeriod
        .awaiting_rollover
        .joins(:subscription)
        .where(subscriptions: {status: :active})
      scope = scope.where("subscription_billing_periods.subscription_id > ?", cursor) if cursor

      subscription_ids = scope
        .order("subscription_billing_periods.subscription_id")
        .distinct
        .limit(BATCH_SIZE)
        .pluck("subscription_billing_periods.subscription_id")
      return if subscription_ids.empty?

      subscription_ids.each { |id| Subscriptions::BillingPeriods::UpsertJob.perform_later(id) }

      self.class.perform_later(subscription_ids.last)
    end
  end
end
