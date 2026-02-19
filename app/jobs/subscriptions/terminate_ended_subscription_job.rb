# frozen_string_literal: true

module Subscriptions
  class TerminateEndedSubscriptionJob < ApplicationJob
    retry_on Customers::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    unique :until_executed, on_conflict: :log

    def perform(subscription)
      Subscriptions::TerminateService.call!(subscription:)
    end
  end
end
