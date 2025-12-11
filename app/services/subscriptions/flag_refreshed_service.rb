#  frozen_string_literal: true

module Subscriptions
  class FlagRefreshedService < BaseService
    Result = BaseResult[:subscription_id]

    def initialize(subscription_id)
      @subscription_id = subscription_id
      super
    end

    def call
      subscription.customer.flag_wallets_for_refresh
      UsageMonitoring::TrackSubscriptionActivityService.call(subscription:)

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
