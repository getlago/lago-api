# frozen_string_literal: true

module BillingSegments
  # Bills a subscription's due segments right away (used after subscription creation so
  # advance items invoice immediately). Enqueued after commit; the clock would pick the
  # same segments up on its next tick, so this only shortens the delay.
  class BillSubscriptionJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    def perform(subscription)
      BillingSegments::BillSubscriptionService.call!(subscription:)
    end
  end
end
