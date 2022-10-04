# frozen_string_literal: true

module Subscriptions
  class ActivateService < BaseService
    def activate_all_pending
      Subscription
        .pending
        .where(previous_subscription: nil)
        .where(subscription_date: Time.current.to_date)
        .find_each do |subscription|
          subscription.mark_as_active!

          BillSubscriptionJob.perform_later([subscription], Time.current.to_i) if subscription.plan.pay_in_advance?
        end
    end
  end
end
