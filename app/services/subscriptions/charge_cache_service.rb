# frozen_string_literal: true

module Subscriptions
  class ChargeCacheService < CacheService
    # Bumped to "2" when lazy validation was introduced: it stores a different value shape (wrapped
    # with its creation time) than the legacy eager-invalidation entries.
    CACHE_KEY_VERSION = "2"

    def self.expire_for_subscriptions(subscription_ids)
      Subscription
        .where(id: subscription_ids)
        .preload(plan: {charges: :filters})
        .find_each do |subscription|
          subscription.plan.charges.each do |charge|
            expire_for_subscription_charge(subscription:, charge:)
          end
        end
    end

    def self.expire_for_subscription(subscription)
      expire_for_subscriptions([subscription.id])
    end

    def self.expire_for_subscription_charge(subscription:, charge:)
      charge.filters.each do |filter|
        expire_cache(subscription:, charge:, charge_filter: filter)
      end

      expire_cache(subscription:, charge:)
    end

    def initialize(subscription:, charge:, charge_filter: nil, expires_in: nil, invalidate_if_older_than: nil)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter

      super(expires_in:, invalidate_if_older_than:)
    end

    # IMPORTANT
    # when making changes here, please make sure to bump the cache key so old values are immediately invalidated!
    def cache_key
      [
        "charge-usage",
        CACHE_KEY_VERSION,
        charge.id,
        subscription.id,
        charge.updated_at.iso8601,
        charge_filter&.id,
        charge_filter&.updated_at&.iso8601
      ].compact.join("/")
    end

    private

    attr_reader :subscription, :charge, :charge_filter

    def track_created_at?
      true
    end
  end
end
