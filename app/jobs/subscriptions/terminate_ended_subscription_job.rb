# frozen_string_literal: true

module Subscriptions
  # Handles async termination of ended subscriptions from `Clock::TerminateEndedSubscriptionsJob`.
  # Intentionally on the `default` queue: this job only triggers termination which schedules
  # billing separately — it doesn't perform billing itself, so it shouldn't compete
  # with billing jobs on the :billing queue.
  class TerminateEndedSubscriptionJob < ApplicationJob
    retry_on Customers::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    unique :until_executed, on_conflict: :log

    def perform(subscription)
      Subscriptions::TerminateService.call!(subscription:)
    end
  end
end
