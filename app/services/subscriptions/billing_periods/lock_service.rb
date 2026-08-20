# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # Serializes the writers of one subscription's billing periods: the lifecycle services and the
    # refresh jobs write the same rows, and the overlap constraint is deferred, so a writer that
    # commits in the middle of another is only caught at COMMIT — by then it is the enclosing
    # lifecycle transaction that fails.
    #
    # Usage in jobs:
    #   retry_on BaseLockService::FailedToAcquireLock,
    #            attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay
    #
    class LockService < BaseLockService
      def initialize(subscription:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
        @subscription = subscription

        super(timeout_seconds:, transaction:)
      end

      private

      attr_reader :subscription

      def lock_owner
        SubscriptionBillingPeriod
      end

      def lock_key
        "subscription-billing-periods-#{subscription.id}"
      end
    end
  end
end
