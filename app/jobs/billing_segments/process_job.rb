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

    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    # The service finalizes inline, and invoice numbering serialises per billing entity: two
    # customers of the same entity finishing together raise here. Without the retry the job
    # dies on the first attempt and leaves its invoice stuck in generating.
    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

    def perform(customer_id)
      ProcessService.call!(customer: Customer.find(customer_id))
    end
  end
end
