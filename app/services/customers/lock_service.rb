# frozen_string_literal: true

module Customers
  class LockService < BaseService
    ACQUIRE_LOCK_TIMEOUT = 5.seconds
    VALID_SCOPES = %i[prepaid_credit].freeze

    def initialize(customer:, scope:, timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
      @customer = customer
      @scope = scope
      @timeout_seconds = timeout_seconds
      @transaction = transaction

      validate_scope!

      super
    end

    def call
      Customer.with_advisory_lock!(lock_key, timeout_seconds:, transaction:) do
        yield
      end
    rescue WithAdvisoryLock::FailedToAcquireLock
      raise FailedToAcquireLock, "Failed to acquire lock #{lock_key}"
    end

    def locked?
      ActiveRecord::Base.advisory_lock_exists?(lock_key)
    end

    private

    attr_reader :customer, :scope, :timeout_seconds, :transaction

    def validate_scope!
      return if VALID_SCOPES.include?(scope)

      raise ArgumentError, "Invalid scope: #{scope}. Valid scopes are: #{VALID_SCOPES.join(", ")}"
    end

    def lock_key
      "customer-#{customer.id}-#{scope}"
    end
  end
end
