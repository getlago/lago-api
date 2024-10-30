# frozen_string_literal: true

module Subscriptions
  class ChargeCacheService
    CACHE_KEY_VERSION = '1'

    def self.expire_for_subscription(subscription)
      subscription.plan.charges.includes(:filters)
        .find_each { expire_for_subscription_charge(subscription:, charge: _1) }
    end

    def self.expire_for_subscription_charge(subscription:, charge:)
      charge.filters.each do |filter|
        new(subscription:, charge:, charge_filter: filter).expire_cache
      end

      new(subscription:, charge:).expire_cache
    end

    def initialize(subscription:, charge:, charge_filter: nil)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
    end

    # IMPORTANT
    # when making changes here, please make sure to bump the cache key so old values are immediately invalidated!
    def cache_key
      [
        'charge-usage',
        CACHE_KEY_VERSION,
        charge.id,
        subscription.id,
        charge.updated_at.iso8601,
        charge_filter&.id,
        charge_filter&.updated_at&.iso8601
      ].compact.join('/')
    end

    def expire_cache
      Rails.cache.delete(cache_key)
    end

    private

    attr_reader :subscription, :charge, :charge_filter
  end
end
