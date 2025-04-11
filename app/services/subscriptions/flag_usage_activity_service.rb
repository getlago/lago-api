# frozen_string_literal: true

module Subscriptions
  class FlagUsageActivityService < BaseService
    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      return result unless subscription.active?
      return result unless should_flag_subscription?

      usage_activity = subscription.usage_activity
      usage_activity ||= Subscription::UsageActivity
        .new(subscription:, organization_id: subscription.customer.organization_id)

      usage_activity.recalculate_current_usage = true
      usage_activity.save!
      result.usage_activity = usage_activity

      result
    end

    private

    attr_reader :subscription

    def should_flag_subscription?
      subscription.organization.lifetime_usage_enabled? ||
        subscription.plan.usage_thresholds.any? ||
        subscription.organization.alerting_total_usage_enabled?
    end
  end
end
