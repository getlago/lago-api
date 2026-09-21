# frozen_string_literal: true

module BillingSegments
  class ScheduleJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(customer_id)
      ScheduleService.call!(customer: Customer.find(customer_id))
    end
  end
end
