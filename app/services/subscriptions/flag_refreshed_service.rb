#  frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Subscriptions
  class FlagRefreshedService < BaseService
    Result = BaseResult[:subscription_id]

    def initialize(subscription_id)
      @subscription_id = subscription_id
      super
    end

    def call
      customer = subscription.customer
      customer.flag_wallets_for_refresh
      date = Time.current.in_time_zone(customer.applicable_timezone).to_date
      UsageMonitoring::TrackSubscriptionActivityService.call(subscription:, date:)

      result.subscription_id = subscription_id
      result
    end

    private

    attr_reader :subscription_id

    def subscription
      @subscription ||= Subscription.find(subscription_id)
    end
  end
end
