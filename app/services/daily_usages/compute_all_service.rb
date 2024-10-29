# frozen_string_literal: true

module DailyUsages
  class ComputeAllService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      subscriptions.find_each do |subscription|
        DailyUsages::ComputeJob.perform_later(subscription, timestamp:)
      end

      result
    end

    private

    attr_reader :timestamp

    def subscriptions
      # NOTE(DailyUsage): For now the query filters organizations having revenue_analytics premium integrations
      #                   This might change in the future
      Subscription
        .with(already_refreshed_today: already_refreshed_today)
        .joins(customer: :organization)
        .merge(Organization.with_revenue_analytics_support)
        .joins("LEFT JOIN already_refreshed_today ON subscriptions.id = already_refreshed_today.subscription_id")
        .active
        .where("already_refreshed_today.subscription_id IS NULL") # Exclude subscriptions that already have a daily usage record for today in customer's timezone
        .where("DATE_PART('hour', (:timestamp#{at_time_zone})) IN (0, 1, 2)", timestamp:) # Refresh the usage as soom as a subscription starts a new day in customer's timezone
    end

    def already_refreshed_today
      DailyUsage.refreshed_at_in_timezone(timestamp).select(:subscription_id)
    end
  end
end
