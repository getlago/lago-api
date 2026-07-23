# frozen_string_literal: true

module Customers
  # Acquires a PostgreSQL advisory lock scoped to a customer and a scope to prevent concurrent
  # operations of the same kind on that customer. Each scope maps to an independent lock, so
  # operations in different scopes never block one another.
  #
  # Usage in jobs:
  #   retry_on BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError,
  #            attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay
  #
  # - FailedToAcquireLock: Raised when the advisory lock cannot be acquired within the timeout.
  # - StaleObjectError: For the :prepaid_credit scope, other code paths (e.g., wallet top-ups via
  #   IncreaseService) can update wallets without acquiring this lock. Since Wallet uses optimistic
  #   locking (lock_version), concurrent updates will raise StaleObjectError.
  #
  class LockService < BaseLockService
    VALID_SCOPES = %i[prepaid_credit payment_method credit_note coupon integration_customer].freeze

    def initialize(customer:, scope:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
      @customer = customer
      @scope = scope

      validate_scope!

      super(timeout_seconds:, transaction:)
    end

    private

    attr_reader :customer, :scope

    def lock_owner
      Customer
    end

    def validate_scope!
      return if VALID_SCOPES.include?(scope)

      raise ArgumentError, "Invalid scope: #{scope}. Valid scopes are: #{VALID_SCOPES.join(", ")}"
    end

    def lock_key
      "customer-#{customer.id}-#{scope}"
    end
  end
end
