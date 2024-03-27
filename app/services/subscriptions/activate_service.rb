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
        .where("DATE(subscriptions.subscription_at#{Utils::TimezoneService.at_time_zone}) <= " \
               "DATE(?#{Utils::TimezoneService.at_time_zone})", Time.zone.at(timestamp))
        .find_each do |subscription|
          subscription.mark_as_active!(Time.zone.at(timestamp))

          SendWebhookJob.perform_later("subscription.started", subscription)

          BillSubscriptionJob.perform_later([subscription], timestamp) if subscription.plan.pay_in_advance?
        end
    end

    private

    attr_reader :timestamp
  end
end
