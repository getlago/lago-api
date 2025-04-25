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
      flag_lifetime_usage_for_refresh

      result.subscription_id = subscription_id
      result
    end

    private

    attr_reader :subscription_id

    def flag_wallets_for_refresh
      Wallet
        .active
        .joins(:customer)
        .where(customers: {id: Subscription.where(id: subscription_id).select(:customer_id)})
        .update_all(ready_to_be_refreshed: true)
    end

    def flag_lifetime_usage_for_refresh
      Subscription.where(id: subscription_id).includes(:lifetime_usage, plan: :usage_thresholds).find_each do
        LifetimeUsages::FlagRefreshFromSubscriptionService.new(subscription: _1).call
      end
    end
  end
end
