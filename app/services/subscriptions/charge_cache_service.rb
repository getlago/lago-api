# frozen_string_literal: true

module Subscriptions
  class ChargeCacheService < CacheService
    CACHE_KEY_VERSION = "1"
    # Lazy validation stores a different value shape (wrapped with its creation time), so it uses
    # its own version. Enabling the feature flag gradually migrates an organization's entries to
    # this version instead of invalidating every organization's cache at once.
    LAZY_CACHE_KEY_VERSION = "2"

    # Full usage aggregates from subscription.started_at, not the current period start. The two
    # windows can coincide, but started_at is editable, so they never share an entry.
    FULL_USAGE_KEY_SEGMENT = "full-usage"

    def self.expire_for_subscriptions(subscription_ids)
      Subscription
        .where(id: subscription_ids)
        .preload(:organization, plan: {charges: :filters})
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

    # NOTE: Both entries are cleared. Deleting a billable metric or de-duplicating events removes
    #       usage without advancing the ingestion watermark, so lazy validation would keep serving a
    #       full usage entry left behind here.
    def self.expire_cache(subscription:, charge:, charge_filter: nil)
      new(subscription:, charge:, charge_filter:).expire_cache
      new(subscription:, charge:, charge_filter:, full_usage: true).expire_cache
    end

    def initialize(subscription:, charge:, charge_filter: nil, full_usage: false, expires_in: nil, invalidate_if_older_than: nil)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @full_usage = full_usage

      super(expires_in:, invalidate_if_older_than:)
    end

    # IMPORTANT
    # when making changes here, please make sure to bump the cache key so old values are immediately invalidated!
    def cache_key
      [
        "charge-usage",
        cache_key_version,
        charge.id,
        subscription.id,
        charge.updated_at.iso8601,
        charge_filter&.id,
        charge_filter&.updated_at&.iso8601,
        (FULL_USAGE_KEY_SEGMENT if full_usage)
      ].compact.join("/")
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :full_usage

    def cache_key_version
      lazy_validation? ? LAZY_CACHE_KEY_VERSION : CACHE_KEY_VERSION
    end

    def track_created_at?
      lazy_validation?
    end

    def lazy_validation?
      return @lazy_validation if defined?(@lazy_validation)

      @lazy_validation = subscription.organization.feature_flag_enabled?(:lazy_charge_usage_cache)
    end
  end
end
