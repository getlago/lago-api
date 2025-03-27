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

    retry_on Sequenced::SequenceError
    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
    retry_on ActiveJob::Uniqueness::JobNotUnique, wait: :polynomially_longer, attempts: 25

    unique :until_executed

    def perform(charge:, event:, timestamp:, invoice: nil)
      result = Invoices::CreatePayInAdvanceChargeService.call(charge:, event:, timestamp:, invoice:)
      return if result.success?
      # NOTE: We don't want a dead job for failed invoice due to the tax reason.
      #       This invoice should be in failed status and can be retried.
      return if tax_error?(result)

      result.raise_if_error! if invoice || result.invoice.nil? || !result.invoice.generating?

      # NOTE: retry the job with the already created invoice in a previous failed attempt
      self.class.set(wait: 3.seconds).perform_later(
        charge:,
        event:,
        timestamp:,
        invoice: result.invoice
      )
    ensure
      unlock_unique_job
    end

    def lock_key_arguments
      args = arguments.first
      event = Events::CommonFactory.new_instance(source: args[:event])
      [args[:charge], event.organization_id, event.external_subscription_id]
    end

    private

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error).present?
    end

    def unlock_unique_job
      lock_key = ActiveJob::Uniqueness::LockKey.new(self).key
      Sidekiq.redis { |conn| conn.del(lock_key) }
    rescue => e
      Rails.logger.error "Failed to release lock: #{e.message}"
    end
  end
end
