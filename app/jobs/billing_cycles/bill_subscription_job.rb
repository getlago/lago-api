# frozen_string_literal: true

module BillingCycles
  # Bills a subscription's due cycles right away (used after subscription creation so
  # advance items invoice immediately). Enqueued after commit; the clock would pick the
  # same cycles up on its next tick, so this only shortens the delay.
  class BillSubscriptionJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(subscription)
      BillingCycles::BillSubscriptionService.call!(subscription:)
    end
  end
end
