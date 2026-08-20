# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    class RefreshAllJob < ApplicationJob
      queue_as :low_priority

      # The lock is released when the job starts rather than when it finishes: a timezone change
      # committing while a walk is running may have been missed by the subscriptions it already
      # went past, so the enqueue it makes must not be dropped as a duplicate.
      unique :until_executing, on_conflict: :log

      # Self-chaining: the service enqueues one page of subscriptions and hands back the cursor to
      # resume from, so a billing entity owning hundreds of thousands of them is walked over short
      # runs instead of one job holding a connection for all of them.
      def perform(owner, cursor = nil)
        result = Subscriptions::BillingPeriods::RefreshAllService.call!(owner:, cursor:)

        self.class.perform_later(owner, result.next_cursor) if result.next_cursor
      end
    end
  end
end
