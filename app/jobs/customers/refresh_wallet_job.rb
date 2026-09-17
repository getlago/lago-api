# frozen_string_literal: true

module Customers
  class RefreshWalletJob < ApplicationJob
    queue_as do
      customer = arguments.first
      Utils::DedicatedWorkerConfig.queue_for(
        customer&.organization_id,
        dedicated: Utils::DedicatedWorkerConfig::DEDICATED_WALLETS_QUEUE,
        default: ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_WALLETS"]) ? :wallets : :low_priority
      )
    end

    unique :until_executed, on_conflict: :log, lock_ttl: 2.hours

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6

    # WalletRefreshConsumer refreshes the same customers inline, so the lock is now contended
    # across lanes.
    retry_on(
      BaseLockService::FailedToAcquireLock,
      wait: random_lock_retry_delay,
      attempts: MAX_LOCK_RETRY_ATTEMPTS
    )

    retry_on(
      BaseService::TooManyProviderRequestsFailure,
      wait: linear_delay(5, max_seconds: 30),
      attempts: 10
    ) do |job, error|
      # Giving up is not a failure: the provider rate limit is shared and the clock job will
      # pick the customer up again.
      # Logged rather than raised to keep sustained throttling out of the dead set.
      Rails.logger.warn(
        "RefreshWalletJob reached max throttling retry attempts" \
        "customer_id=#{job.arguments.first&.id} provider=#{error.provider_name}"
      )

      # The uniqueness lock is only released by the `after_perform` callback, which is skipped
      # when the job raises. Swallowing the error here also bypasses Sidekiq's death handler, so
      # the lock must be released explicitly: otherwise the customer stays locked for `lock_ttl`
      # and every re-enqueue from the clock job is silently dropped on conflict.
      job.lock_strategy.unlock(resource: job.lock_key)
    end

    retry_on(*Integrations::Aggregator::BaseService.retryable_errors, wait: :polynomially_longer, attempts: 6)

    # wallet_ids marks an explicitly requested refresh (e.g. balance increase) that must run even
    # when the customer-wide awaiting_wallet_refresh flag is not set. The refresh itself always
    # covers every wallet: the cascade makes allocations interdependent.
    def perform(customer, wallet_ids: nil)
      Customers::RefreshWalletService.call!(customer:, force: !wallet_ids.nil?)
    end
  end
end
