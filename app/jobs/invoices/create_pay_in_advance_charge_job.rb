# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75
    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

    retry_on BaseLockService::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    # DEPRECATED: These errors should not be raised anymore but we keep them and monitor to be sure.
    retry_on ActiveRecord::LockWaitTimeout, PG::LockNotAvailable, queue: :low_priority, wait: :polynomially_longer, attempts: 15

    unique :until_executed, on_conflict: :log

    def perform(timestamp:, charge: nil, metered_item: nil, event: nil, invoice: nil)
      result = Invoices::CreatePayInAdvanceChargeService.call(
        metered_item: pay_in_advance_arguments.metered_item,
        timestamp:
      )
      return if result.success?
      # NOTE: We don't want a dead job for failed invoice due to the tax reason.
      #       This invoice should be in failed status and can be retried.
      return if tax_error?(result)

      result.raise_if_error!
    end

    delegate :lock_key_arguments, to: :pay_in_advance_arguments

    private

    def pay_in_advance_arguments
      job_arguments = arguments.first
      @pay_in_advance_arguments ||= PayInAdvanceArguments.new(
        metered_item: job_arguments[:metered_item] || job_arguments["metered_item"],
        charge: job_arguments[:charge] || job_arguments["charge"],
        event: job_arguments[:event] || job_arguments["event"]
      )
    end

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error).present?
    end
  end
end
