# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    class UpsertJob < ApplicationJob
      queue_as :low_priority

      unique :until_executed, on_conflict: :log

      # Takes an id: the rollover sweep enqueues these a page at a time, and a record argument would
      # cost one lookup per enqueue to serialize.
      def perform(subscription_id)
        subscription = Subscription.find_by(id: subscription_id)
        return if subscription.nil?

        # Skipped rather than queued when another writer holds the lock, since it is about to write
        # the same rows.
        Subscription.with_advisory_lock("subscription_billing_periods_#{subscription.id}", timeout_seconds: 0) do
          Subscriptions::BillingPeriods::UpsertService.call!(subscription:)
        end
      end
    end
  end
end
