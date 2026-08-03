# frozen_string_literal: true

module LifetimeUsages
  class RecalculateAndCheckJob < ApplicationJob
    # Raised when the inline (perform_now) invocation cannot resolve a lock conflict within
    # MAX_LOCK_RETRY_ATTEMPTS. It intentionally is NOT a class listed in `retry_on`, so the
    # lock conflict never triggers an ActiveJob retry (which would fail to serialize the
    # non-serializable current_usage). The original lock error is preserved as `cause`.
    class InlineLockRetryExhausted < StandardError; end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing_low_priority
      else
        :default
      end
    end

    retry_on BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    # This job can run concurrently for the same lifetime usage (the clock's async
    # sweep and the inline perform_now from subscription activity processing don't
    # share the uniqueness lock). When they race on the same passed threshold, the
    # losing run raises an IdempotencyError because the progressive billing invoice
    # was already created by the winning run. That is a benign no-op, not a failure
    # to retry, so we discard it instead of letting it exhaust retries and pile up
    # in the dead set.
    discard_on Idempotency::IdempotencyError

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    # NOTE: do not pass current usage with perform_later as it will be a huge JSON
    def perform(lifetime_usage, current_usage: nil)
      # When invoked inline via perform_now, current_usage is a non-serializable
      # SubscriptionUsage struct. A lock conflict must be retried in-process here:
      # reaching ActiveJob's retry_on would try to re-enqueue the job and fail to
      # serialize current_usage. The async perform_later path (current_usage nil) keeps
      # relying on retry_on so it does not hold a worker while waiting between attempts.
      if current_usage
        perform_with_inline_lock_retry(lifetime_usage, current_usage)
      else
        process(lifetime_usage, current_usage:)
      end
    end

    def lock_key_arguments
      [arguments.first]
    end

    private

    def process(lifetime_usage, current_usage:)
      LifetimeUsages::CalculateService.call!(lifetime_usage:, current_usage:)

      if lifetime_usage.organization.progressive_billing_enabled?
        LifetimeUsages::CheckThresholdsService.call!(lifetime_usage:)
      end
    end

    def perform_with_inline_lock_retry(lifetime_usage, current_usage)
      attempts = 0

      begin
        process(lifetime_usage, current_usage:)
      rescue BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError => e
        attempts += 1

        if attempts < MAX_LOCK_RETRY_ATTEMPTS
          sleep rand(0...MAX_LOCK_RETRY_DELAY)
          retry
        end

        # Break the cause chain (cause: nil): ActiveJob's retry_on matches the exception's
        # cause too, so keeping the lock error as cause would still trigger a retry and fail
        # to serialize current_usage. The original error is kept in the message.
        raise InlineLockRetryExhausted.new(
          "Lock conflict unresolved after #{attempts} in-process retries: #{e.class}: #{e.message}"
        ), cause: nil
      end
    end
  end
end
