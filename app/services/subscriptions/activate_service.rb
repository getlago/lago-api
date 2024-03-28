# frozen_string_literal: true

module Subscriptions
  class ActivateService < BaseService
    def initialize(timestamp:)
      @timestamp = timestamp

      super(nil)
    end

    def activate_all_pending
      Subscription
        .joins(customer: :organization)
        .pending
        .where(previous_subscription: nil)
        .where(
          "DATE(subscriptions.subscription_at#{at_time_zone}) <= " \
          "DATE(?#{at_time_zone})",
          Time.zone.at(timestamp),
        )
        .find_each do |subscription|
          subscription.mark_as_active!(Time.zone.at(timestamp))

          SendWebhookJob.perform_later('subscription.started', subscription)

          if subscription.plan.pay_in_advance? && !subscription.in_trial_period?
            BillSubscriptionJob.perform_later([subscription], timestamp)
          end
        end
    end

    private

    attr_reader :timestamp
  end
end
