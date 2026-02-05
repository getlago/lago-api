# frozen_string_literal: true

module Invoices
  class CreatePayInAdvanceFixedChargesJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on Customers::FailedToAcquireLock, attempts: 25, wait: ->(_) { rand(0...16) }

    def perform(subscription, timestamp)
      result = Invoices::CreatePayInAdvanceFixedChargesService.call(
        subscription:,
        timestamp:
      )

      return if result.success?

      # NOTE: We don't want a dead job for failed invoice due to the tax reason.
      #       This invoice should be in failed status and can be retried.
      return if tax_error?(result)

      result.raise_if_error!
    end

    private

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error.messages&.dig(:tax_error).present?
    end
  end
end
