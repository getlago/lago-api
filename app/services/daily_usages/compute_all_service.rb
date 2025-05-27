# frozen_string_literal: true

module DailyUsages
  class ComputeAllService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      subscriptions.find_each do |subscription|
        DailyUsages::ComputeJob.set(wait: rand(30.minutes)).perform_later(subscription, timestamp:)
      end

      result
    end

    private

    attr_reader :timestamp

    def subscriptions
      # NOTE(DailyUsage): For now the query filters organizations having revenue_analytics premium integrations
      #                   This might change in the future
      Subscription
        .with(existing_daily_usage:)
        .joins(customer: [:organization, :billing_entity])
        .merge(Organization.with_revenue_analytics_support)
        .joins("LEFT JOIN existing_daily_usage ON subscriptions.id = existing_daily_usage.subscription_id")
        .active
        .where("existing_daily_usage.subscription_id IS NULL") # Exclude subscriptions that already have a daily usage record for yesterday in customer's timezone
        .where("DATE_PART('hour', (:timestamp#{at_time_zone})) IN (0, 1, 2)", timestamp:) # Store the usage as soon as a subscription starts a new day in customer's timezone
    end

    def existing_daily_usage
      DailyUsage.usage_date_in_timezone(timestamp.to_date - 1.day).select(:subscription_id)
    end
  end
end
