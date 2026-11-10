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

    # Temporary tax provider failures: retried, then given up without a dead job.
    GIVE_UP_ERRORS = [
      Integrations::Aggregator::ServerError,
      Integrations::Aggregator::BadGatewayError,
      Integrations::Aggregator::RequestLimitError,
      Integrations::Aggregator::TaskInProgressError,
      Integrations::Aggregator::TaskExpiredError,
      Integrations::Aggregator::OrchestratorFailureError
    ].freeze

    unique :until_executed, on_conflict: :log, lock_ttl: 2.hours

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6

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

      release_lock(job)
    end

    retry_on(*(Integrations::Aggregator::BaseService.retryable_errors - GIVE_UP_ERRORS), wait: :polynomially_longer, attempts: 6)

    retry_on(*GIVE_UP_ERRORS, wait: :polynomially_longer, attempts: 6) do |job, error|
      # A temporary tax provider failure is not a failure of the refresh: the customer stays
      # flagged so the clock job refreshes its wallets once the provider answers again.
      customer = job.arguments.first

      Rails.logger.warn(
        "RefreshWalletJob reached max temporary tax provider error retry attempts " \
        "customer_id=#{customer.id} error=#{error.class.name}"
      )

      customer.flag_wallets_for_refresh
      release_lock(job)
    end

    # The uniqueness lock is only released by the `after_perform` callback, which is skipped
    # when the job raises. Swallowing the error in a give-up block also bypasses Sidekiq's death
    # handler, so the lock must be released explicitly: otherwise the customer stays locked for
    # `lock_ttl` and every re-enqueue from the clock job is silently dropped on conflict.
    def self.release_lock(job)
      job.lock_strategy.unlock(resource: job.lock_key)
    end
    private_class_method :release_lock

    def perform(customer, wallet_ids: nil)
      # wallet_ids marks an explicitly requested refresh (e.g. balance increase) that must run
      # even when the customer-wide awaiting_wallet_refresh flag is not set. The refresh itself
      # always covers every wallet: the cascade makes allocations interdependent.
      return if wallet_ids.nil? && !customer.awaiting_wallet_refresh?
      return if customer.error_details.tax_error.exists?

      Customers::RefreshWalletsService.call!(customer:, raise_on_server_error: true)
    rescue BaseService::ValidationFailure => e
      tax_error = Array(e.messages[:tax_error])

      raise unless tax_error.any? { |msg| msg.include?(Integrations::Aggregator::Taxes::BaseService::CUSTOMER_ADDRESS_INVALID) }

      ErrorDetails::CreateService.call!(
        owner: customer,
        organization: customer.organization,
        params: {
          error_code: :tax_error,
          details: {
            tax_error: e.messages[:tax_error]&.first,
            backtrace: e.backtrace,
            error: e.inspect.to_json
          }.compact
        }
      )
    end
  end
end
