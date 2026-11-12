# frozen_string_literal: true

module Subscriptions
  # Acquires a PostgreSQL advisory lock scoped to a subscription. Progressive billing invoices
  # take it so that two triggers cannot credit the same previous progressive billing invoice.
  class LockService < BaseLockService
    def initialize(subscription:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
      @subscription = subscription

      super(timeout_seconds:, transaction:)
    end

    private

    attr_reader :subscription

    def lock_owner
      Subscription
    end

    def lock_key
      "subscription-#{subscription.id}"
    end
  end
end
