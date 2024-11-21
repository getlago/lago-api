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

      daily_usage = DailyUsage.new(
        organization: subscription.organization,
        customer: subscription.customer,
        subscription:,
        external_subscription_id: subscription.external_id,
        usage: ::V1::Customers::UsageSerializer.new(current_usage, includes: %i[charges_usage]).serialize,
        from_datetime: current_usage.from_datetime,
        to_datetime: current_usage.to_datetime,
        refreshed_at: timestamp
      )

      daily_usage.usage_diff = diff_usage(daily_usage)
      daily_usage.save!

      result.daily_usage = daily_usage
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
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
      @existing_daily_usage ||= DailyUsage.refreshed_at_in_timezone(timestamp)
        .find_by(subscription_id: subscription.id)
    end

    def diff_usage(daily_usage)
      DailyUsages::ComputeDiffService.call!(daily_usage:).usage_diff
    end
  end
end
