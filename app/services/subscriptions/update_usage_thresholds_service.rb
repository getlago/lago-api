# frozen_string_literal: true

module Subscriptions
  class UpdateUsageThresholdsService < BaseService
    Result = BaseResult[:subscription]

    def initialize(subscription:, usage_thresholds_params:, partial:)
      @subscription = subscription
      @usage_thresholds_params = usage_thresholds_params
      @partial = partial
      super
    end

    def call
      result.subscription = subscription

      return result unless subscription.organization.progressive_billing_enabled?

      ut_result = UsageThresholds::UpdateService.call(model: subscription, usage_thresholds_params:, partial:)
      return ut_result unless ut_result.success?

      subscription.usage_thresholds.reload
      subscription.lifetime_usage.update recalculate_invoiced_usage: true if subscription.usage_thresholds.size > 0

      result
    end

    private

    attr_reader :subscription, :usage_thresholds_params, :partial
  end
end
