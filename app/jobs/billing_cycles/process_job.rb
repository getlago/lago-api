# frozen_string_literal: true

module BillingCycles
  class ProcessJob < ApplicationJob
    # One in-flight processor per customer: avoids two runs double-invoicing the same
    # pending cycles (the advisory lock in the service is the correctness backstop).
    # lock_ttl auto-expires the lock so a crashed job never blocks that customer forever.
    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    # Invoice finalization (numbering) happens inline in ProcessService and serialises per
    # billing_entity; under contention it raises SequenceError, which we retry (mirrors the
    # legacy BillSubscriptionJob). ProcessService's reconcile makes the retry idempotent.
    retry_on Customers::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay
    retry_on Sequenced::SequenceError, wait: :polynomially_longer, attempts: 15, jitter: 0.75

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(customer_id)
      customer = Customer.find(customer_id)
      BillingCycles::ProcessService.call!(customer:)
    end
  end
end
