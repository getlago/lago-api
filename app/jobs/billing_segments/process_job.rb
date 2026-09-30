# frozen_string_literal: true

module BillingSegments
  class ProcessJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    unique :until_executing, on_conflict: :log, lock_ttl: 30.minutes

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay
    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

    def perform(customer_id)
      ProcessService.call!(customer: Customer.find(customer_id))
    end
  end
end
