# frozen_string_literal: true

module LifetimeUsages
  class FlagRefreshFromSubscriptionService < BaseService
    Result = BaseResult[:lifetime_usage]

    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      return result unless subscription.active?
      return result unless should_flag_refresh_from_subscription?

      lifetime_usage = subscription.lifetime_usage
      lifetime_usage ||= subscription.build_lifetime_usage(organization: subscription.organization)
      lifetime_usage.recalculate_current_usage = true
      lifetime_usage.save!

      result.lifetime_usage = lifetime_usage

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription

    def should_flag_refresh_from_subscription?
      subscription.organization.lifetime_usage_enabled? || subscription.plan.usage_thresholds.any?
    end
  end
end
