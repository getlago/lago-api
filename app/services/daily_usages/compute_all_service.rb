# frozen_string_literal: true

module DailyUsages
  class ComputeAllService < BaseService
    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      return result unless ENV['LAGO_ENABLE_REVENUE_ANALYTICS'].present?

      subscriptions.find_each do |subscription|
        DailyUsages::ComputeJob.perform_later(subscription, timestamp:)
      end

      return result
    end

    private

    attr_reader :timestamp

    def subscriptions
      # TODO: Filter subscriptions based on the feature availability at organization level
      Subscription
        .with(already_refreshed_today: already_refreshed_today)
        .joins(customer: :organization)
        .joins('LEFT JOIN already_refreshed_today ON subscriptions.id = already_refreshed_today.subscription_id')
        .active
        .where('already_refreshed_today.subscription_id IS NULL') # Exclude subscriptions that already have a daily usage record for today in customer's timezone
        .where("DATE_PART('hour', (:timestamp#{at_time_zone})) IN (0, 1, 2)", timestamp:) # Refresh the usage as soom as a subscription starts a new day in customer's timezone
    end

    def already_refreshed_today
      where_clause = <<-SQL
        DATE(
          (daily_usages.created_at)#{at_time_zone(customer: "cus", organization: "org")}
        ) = DATE(:timestamp#{at_time_zone(customer: "cus", organization: "org")})
      SQL

      DailyUsage
        .joins('INNER JOIN customers AS cus ON daily_usages.customer_id = cus.id')
        .joins('INNER JOIN organizations AS org ON daily_usages.organization_id = org.id')
        .select(:subscription_id)
        .where(where_clause, timestamp:)
    end
  end
end
