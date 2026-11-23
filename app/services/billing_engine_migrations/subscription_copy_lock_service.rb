# frozen_string_literal: true

module BillingEngineMigrations
  # Serializes the copies of one V1 subscription: the on-write job and the backfill job decide from
  # the subscription and the shadow contracts they read, so two copies at once could act on stale
  # state. A session lock, because the copy commits each contract change in its own transaction.
  # Its own key, so a copy never waits on the V1 subscription lock.
  class SubscriptionCopyLockService < BaseLockService
    def initialize(subscription:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT)
      @subscription = subscription

      super(timeout_seconds:, transaction: false)
    end

    private

    attr_reader :subscription

    def lock_owner
      Subscription
    end

    def lock_key
      "billing-engine-migration-subscription-#{subscription.id}"
    end
  end
end
