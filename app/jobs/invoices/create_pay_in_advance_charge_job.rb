# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceChargeJob < ApplicationJob
    def self.retry_delay(attempt)
      rand(0...16)
    end

    CUSTOMER_LOCK_TTL = 60_000 # if a job is stuck or lost for more than 1 minute, we should timeout.
    private_constant :CUSTOMER_LOCK_TTL

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75
    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
    retry_on ActiveRecord::StaleObjectError, ActiveRecord::LockWaitTimeout, PG::LockNotAvailable, queue: :low_priority, wait: :polynomially_longer, attempts: 15
    retry_on Redlock::LockError, attempts: 15, wait: ->(attempt) { CreatePayInAdvanceChargeJob.retry_delay(attempt) }

    unique :until_executed, on_conflict: :log

    def perform(charge:, event:, timestamp:, invoice: nil)
      event = Events::CommonFactory.new_instance(source: event)
      with_customer_lock(event.subscription.customer_id) do
        result = Invoices::CreatePayInAdvanceChargeService.call(charge:, event:, timestamp:)
        next if result.success?
        # NOTE: We don't want a dead job for failed invoice due to the tax reason.
        #       This invoice should be in failed status and can be retried.
        next if tax_error?(result)

        result.raise_if_error!
      end
    end

    def lock_key_arguments
      args = arguments.first
      event = Events::CommonFactory.new_instance(source: args[:event])
      [args[:charge], event.organization_id, event.external_subscription_id, event.transaction_id]
    end

    private

    def with_customer_lock(event, &block)
      Rails.application.config.lock_manager.lock!(event.subscription.customer_id, 10000, &block)
    end

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error).present?
    end
  end
end
