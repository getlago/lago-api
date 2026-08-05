# frozen_string_literal: true

module Analytics
  class Base < ApplicationRecord
    self.abstract_class = true

    VERSION_CACHE_EXPIRATION = 1.day

    def self.find_all_by(organization_id, **args)
      if args[:expire_cache] == true && args[:external_customer_id].present?
        expire_cache_for_customer(organization_id, args[:external_customer_id])
      end

      Rails.cache.fetch(versioned_cache_key(organization_id, **args), expires_in: cache_expiration) do
        sql = query(organization_id, **args)

        result = ActiveRecord::Base.connection.exec_query(sql)
        result.to_a
      end
    end

    def self.cache_expiration
      4.hours
    end

    # Appends a per-customer version token to the cache key so that all the
    # cached variants of a customer (every billing entity / currency / months
    # combination) can be invalidated at once by bumping a single token.
    # Org-level keys (no external_customer_id) are left untouched.
    def self.versioned_cache_key(organization_id, **args)
      key = cache_key(organization_id, **args)
      return key if args[:external_customer_id].blank?

      [key, cache_version(organization_id, args[:external_customer_id])].join("/")
    end

    # Reads the current version token, seeding it with the current timestamp
    # when absent. Using a wall-clock token (instead of a 0-based counter)
    # makes eviction/expiry of the token safe: a regenerated token is always
    # greater than any token a still-cached data key was written with, so a
    # lost token can only ever cause a cold recompute (a miss), never a stale
    # hit.
    def self.cache_version(organization_id, external_customer_id)
      Rails.cache.fetch(
        cache_version_key(organization_id, external_customer_id),
        raw: true,
        expires_in: VERSION_CACHE_EXPIRATION
      ) { Time.current.to_i.to_s }
    end

    def self.expire_cache_for_customer(organization_id, external_customer_id)
      Rails.cache.write(
        cache_version_key(organization_id, external_customer_id),
        Time.current.to_i.to_s,
        raw: true,
        expires_in: VERSION_CACHE_EXPIRATION
      )
    end

    def self.cache_version_key(organization_id, external_customer_id)
      "#{name}/cache-version/#{organization_id}/#{external_customer_id}"
    end
  end
end
