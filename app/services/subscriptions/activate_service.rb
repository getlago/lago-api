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
        .where("DATE(#{Subscription.subscription_date_in_timezone_sql}) = ?", Time.zone.at(timestamp).to_date)
        .find_each do |subscription|
          subscription.mark_as_active!(Time.zone.at(timestamp))

          BillSubscriptionJob.perform_later([subscription], timestamp) if subscription.plan.pay_in_advance?
        end
    end

    private

    attr_reader :timestamp
  end
end
