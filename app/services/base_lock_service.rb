# frozen_string_literal: true

# Base class for advisory-lock services.
#
# This is a thin wrapper around a PostgreSQL advisory lock: it yields the caller's block
# while the lock is held and exposes the block's return value on the result.
#
# Subclasses define `#lock_owner` (the record or model class the lock is scoped to) and
# `#lock_key`.
class BaseLockService < BaseService
  class FailedToAcquireLock < StandardError; end

  Result = BaseResult[:value]

  ACQUIRE_LOCK_TIMEOUT = 5.seconds

  def initialize(timeout_seconds: ACQUIRE_LOCK_TIMEOUT, transaction: true)
    @timeout_seconds = timeout_seconds
    @transaction = transaction

    super()
  end

  def call
    result.value = lock_owner.with_advisory_lock!(
      lock_key,
      timeout_seconds:,
      transaction:,
      disable_query_cache: true
    ) do
      yield
    end

    result
  rescue WithAdvisoryLock::FailedToAcquireLock
    raise FailedToAcquireLock, "Failed to acquire lock #{lock_key}"
  end

  def locked?
    lock_owner.advisory_lock_exists?(lock_key)
  end

  private

  attr_reader :timeout_seconds, :transaction

  def lock_owner
    raise NotImplementedError, "#{self.class} must implement #lock_owner"
  end

  def lock_key
    raise NotImplementedError, "#{self.class} must implement #lock_key"
  end
end
