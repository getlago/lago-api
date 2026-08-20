# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    class UpsertJob < ApplicationJob
      queue_as :low_priority

      retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

      # The lock is released when the job starts rather than when it finishes: the input of a
      # refresh is the customer timezone and the subscription dates as they are read, so an enqueue
      # made while a refresh is already running carries a change that run may have missed and must
      # not be dropped. A retry is an enqueue too, and it would be dropped just the same.
      #
      # Concurrent runs are safe: UpsertService serializes the writers and the write is convergent.
      unique :until_executing, on_conflict: :log

      # Takes an id: the rollover sweep enqueues these a page at a time, and a record argument would
      # cost one lookup per enqueue to serialize.
      #
      # Writers are serialized by UpsertService itself, so that a lifecycle service and a job
      # writing the same rows take the same lock.
      def perform(subscription_id)
        subscription = Subscription.find_by(id: subscription_id)
        return if subscription.nil?

        Subscriptions::BillingPeriods::UpsertService.call!(subscription:)
      end
    end
  end
end
