# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Serializes the snapshot writes of one charge and billing period of a subscription.
  class LockService < BaseLockService
    def initialize(subscription:, charge:, to_datetime:)
      @subscription = subscription
      @charge = charge
      @to_datetime = to_datetime

      # No timeout: a draft invoice refresh does not retry on FailedToAcquireLock
      super(timeout_seconds: nil)
    end

    private

    attr_reader :subscription, :charge, :to_datetime

    def lock_owner
      RecurringAggregationSnapshot
    end

    def lock_key
      "recurring-aggregation-snapshot-#{subscription.id}-#{charge.id}-#{to_datetime.iso8601(6)}"
    end
  end
end
