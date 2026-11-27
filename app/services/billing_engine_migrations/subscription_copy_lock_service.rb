# frozen_string_literal: true

module BillingEngineMigrations
  # Serializes the copies of the V1 subscriptions sharing an external id: each copy decides from the
  # shadow contracts of that external id, and a plan move gives it to a new subscription while the
  # copy of the old one may still run. A session lock, because the copy commits each contract change
  # in its own transaction. Its own key, so a copy never waits on the V1 subscription lock.
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
      "billing-engine-migration-subscription-#{subscription.organization_id}-#{subscription.external_id}"
    end
  end
end
