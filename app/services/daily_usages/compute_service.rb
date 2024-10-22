# frozen_string_literal: true

module DailyUsages
  class ComputeService < BaseService
    def initialize(subscription:, timestamp:)
      @subscription = subscription
      @timestamp = timestamp
      super
    end

    def call
      if existing_daily_usage.present?
        result.daily_usage = existing_daily_usage
        return result
      end

      daily_usage = DailyUsage.create!(
        organization: subscription.organization,
        customer: subscription.customer,
        subscription:,
        external_subscription_id: subscription.external_id,
        usage: ::V1::Customers::UsageSerializer.new(current_usage).serialize.to_json,
        from_datetime: current_usage.from_datetime,
        to_datetime: current_usage.to_datetime, # TODO: persist the timestamp
      )

      result.daily_usage = daily_usage
      result
    end

    private

    attr_reader :subscription, :timestamp

    def current_usage
      @current_usage ||= Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription: subscription,
        apply_taxes: false
      ).raise_if_error!.usage
    end

    def existing_daily_usage
      @existing_daily_usage ||= DailyUsage
        .joins(customer: :organization)
        .where(subscription_id: subscription.id)
        .where("DATE((daily_usages.created_at)#{at_time_zone}) = DATE(:timestamp#{at_time_zone})", timestamp:)
        .first
    end
  end
end
