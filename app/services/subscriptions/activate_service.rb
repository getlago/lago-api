# frozen_string_literal: true

module Subscriptions
  class ActivateService < BaseService
    def initialize(timestamp:)
      @timestamp = timestamp

      super(nil)
    end

    def activate_all_pending
      Subscription
        .pending
        .where(previous_subscription: nil)
        .where(subscription_date: Time.zone.at(timestamp).to_date)
        .find_each do |subscription|
          subscription.mark_as_active!(Time.zone.at(timestamp))

          BillSubscriptionJob.perform_later([subscription], timestamp) if subscription.plan.pay_in_advance?
        end
    end

    private

    attr_reader :timestamp
  end
end
