# frozen_string_literal: true

module BillingOperations
  class ScheduleJob < ApplicationJob
    queue_as do
      ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"]) ? :billing : :default
    end

    unique :until_executing, on_conflict: :log, lock_ttl: 30.minutes

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(customer_id)
      customer = Customer.find(customer_id)
      ScheduleService.call!(customer:)

      ProcessJob.perform_later(customer_id) if customer.billing_operations.due_for_processing(Time.current).exists?
    end
  end
end
