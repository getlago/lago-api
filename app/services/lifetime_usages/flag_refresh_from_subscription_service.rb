# frozen_string_literal: true

module LifetimeUsages
  class FlagRefreshFromSubscriptionService < BaseService
    def initialize(subscription:)
      @subscription = subscription
      super
    end

    def call
      return result unless subscription.active?
      return result unless subscription.plan.usage_thresholds.any?

      lifetime_usage = subscription.lifetime_usage
      lifetime_usage ||= subscription.build_lifetime_usage(organization: subscription.organization)
      lifetime_usage.recalculate_current_usage = true
      lifetime_usage.save!

      result.lifecycle_usage = lifetime_usage

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription
  end
end
