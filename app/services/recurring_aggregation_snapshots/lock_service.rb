# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Serializes the snapshot writes of one key and billing period.
  class LockService < BaseLockService
    def initialize(key:, to_datetime:)
      @key = key
      @to_datetime = to_datetime

      # No timeout: a draft invoice refresh does not retry on FailedToAcquireLock
      super(timeout_seconds: nil)
    end

    private

    attr_reader :key, :to_datetime

    def lock_owner
      key.model
    end

    def lock_key
      key.lock_key(to_datetime)
    end
  end
end
