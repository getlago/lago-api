# frozen_string_literal: true

module BillingOperations
  class ApplyRateChangeJob < ApplicationJob
    queue_as :default
    unique :until_executing, on_conflict: :log

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(customer_id, rate_card_rate_id)
      customer = Customer.find_by(id: customer_id)
      return unless customer

      ApplyRateChangeService.call!(customer:, rate_card_rate_id:)
    end
  end
end
