# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    class UpsertJob < ApplicationJob
      queue_as :low_priority

      unique :until_executed, on_conflict: :log

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
