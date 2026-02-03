# frozen_string_literal: true

module Customers
  class FailedToAcquireLock < StandardError; end

  class LockService < BaseService
    ACQUIRE_LOCK_TIMEOUT = 5.seconds

    def initialize(customer:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
      @customer = customer
      @timeout_seconds = timeout_seconds
      @transaction = transaction

      super
    end

    def call
      lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds:, transaction:) do
        yield
      end

      unless lock_acquired
        raise FailedToAcquireLock
      end

      lock_acquired
    end

    def locked?
      ActiveRecord::Base.advisory_lock_exists?(lock_key)
    end

    private

    attr_reader :customer, :timeout_seconds, :transaction

    def lock_key
      "customer-#{customer.id}"
    end
  end
end
