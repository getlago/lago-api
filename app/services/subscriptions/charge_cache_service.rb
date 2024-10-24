# frozen_string_literal: true

module Subscriptions
  class ChargeCacheService
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

    def cache_key
      [
        'charge-usage',
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
