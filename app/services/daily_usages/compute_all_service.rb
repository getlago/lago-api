# frozen_string_literal: true

module DailyUsages
  class ComputeAllService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      subscriptions.find_in_batches do |subscriptions|
        subscriptions.each do |subscription|
          DailyUsages::ComputeJob.set(wait: job_wait_time).perform_later(subscription, timestamp:)
        end
      end

      result
    end

    private

    attr_reader :timestamp

    def job_wait_time
      # Randomize job wait time to distribute load across the system.
      # This prevents thundering herd effect when processing large batches,
      # and helps interleave jobs from different organizations since subscriptions
      # within the same organization usually have very similar load profiles.
      rand(scheduling_interval)
    end

    def scheduling_interval
      @scheduling_interval ||= begin
        raw_value = ENV["LAGO_DAILY_USAGES_SCHEDULING_INTERVAL_SECONDS"]
        parsed = Integer(raw_value, exception: false) if raw_value
        parsed = nil if parsed && parsed <= 0
        (parsed || 30.minutes).to_i
      end
    end

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
