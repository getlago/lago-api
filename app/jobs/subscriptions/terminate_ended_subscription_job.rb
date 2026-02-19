# frozen_string_literal: true

#
# This job is used for async retries in Clock:TerminateEndedSubscriptionsJob

module Subscriptions
  class TerminateEndedSubscriptionJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    retry_on Customers::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(subscription:)
      Subscriptions::TerminateService.call(subscription:)
    end
  end
end
