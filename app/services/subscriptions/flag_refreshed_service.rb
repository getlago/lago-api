#  frozen_string_literal: true

module Subscriptions
  class FlagRefreshedService < BaseService
    Result = BaseResult[:subscription_id]

    def initialize(subscription_id)
      @subscription_id = subscription_id
      super
    end

    def call
      flag_wallets_for_refresh
      track_subscription_activity

      result.subscription_id = subscription_id
      result
    end

    private

    attr_reader :subscription_id

    def flag_wallets_for_refresh
      Customer
        .where(id: Subscription.where(id: subscription_id).select(:customer_id))
        .update_all(awaiting_wallet_refresh: true) # rubocop:disable Rails/SkipsModelValidations
    end

    def track_subscription_activity
      UsageMonitoring::TrackSubscriptionActivityService.call(
        subscription: Subscription.find(subscription_id)
      )
    end
  end
end
