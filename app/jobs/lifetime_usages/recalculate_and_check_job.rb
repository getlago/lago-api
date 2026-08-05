# frozen_string_literal: true

module LifetimeUsages
  class RecalculateAndCheckJob < ApplicationJob
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
      LifetimeUsages::CalculateService.call!(lifetime_usage:, current_usage:)

      if lifetime_usage.organization.progressive_billing_enabled?
        LifetimeUsages::CheckThresholdsService.call!(lifetime_usage:)
      end
    end

    def lock_key_arguments
      [arguments.first]
    end
  end
end
