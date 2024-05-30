# frozen_string_literal: true

module Subscriptions
  class ChargeCacheService < BaseService
    def self.expire_for_subscription(subscription)
      subscription.plan.charges.each { new(subscription: subscription, charge: _1).expire_cache }
    end

    def initialize(subscription:, charge:)
      @subscription = subscription
      @charge = charge

      super
    end

    def cache_key
      [
        'charge-usage',
        charge.id,
        subscription.id,
        charge.updated_at.iso8601
      ].join('/')
    end

    def expire_cache
      Rails.cache.delete(cache_key)
    end

    private

    attr_reader :subscription, :charge
  end
end
