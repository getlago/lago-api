# frozen_string_literal: true

module UsageAttributions
  # Caches the rows of an attributed usage query under its SQL, so each level, filter, window and page
  # has its own entry, and a pricing change reads into a new one.
  #
  # An entry is served only while no event of the query was ingested after its watermark.
  # enriched_at is stamped when an insert begins, so the watermark trails the read by
  # INGESTION_MARGIN to cover rows that were not readable yet.
  #
  # Deleted events leave no trace the watermark can see, so a deletion expires the entries of its
  # subscription computed before it. MAX_TTL bounds what neither covers, such as duplicates merged
  # by ClickHouse after the read.
  class RowsCacheService < BaseService
    CACHE_KEY_VERSION = "1"
    INGESTION_MARGIN = Events::Stores::ChargeFiltersScan::IncrementalCache::INGESTION_MARGIN
    MAX_TTL = 6.hours
    FAILURE_TTL = 10.seconds

    Result = BaseResult[:rows]

    def self.expire_for_subscription(subscription)
      Rails.cache.write(expiry_key(subscription), Time.current, expires_in: MAX_TTL)
    end

    def self.expiry_key(subscription)
      ["attributed-usage", CACHE_KEY_VERSION, subscription.organization_id, subscription.id, "expired-at"].join("/")
    end

    def initialize(subscription:, query:)
      @subscription = subscription
      @query = query

      super
    end

    def call
      entry = cached_entry

      if entry&.key?("error")
        raise ActiveRecord::StatementInvalid, entry["error"]
      elsif entry
        result.rows = entry["rows"]
      else
        result.rows = compute
      end

      result
    end

    private

    attr_reader :subscription, :query

    def cached_entry
      expiry_key = self.class.expiry_key(subscription)
      entries = Rails.cache.read_multi(cache_key, expiry_key)
      entry = entries[cache_key]
      entry if entry && valid?(entry, entries[expiry_key])
    end

    def valid?(entry, expired_at)
      return true if entry.key?("error")
      return false if expired_at && entry["computed_at"] <= expired_at

      !query.ingested_since?(entry["computed_at"] - INGESTION_MARGIN)
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def compute
      computed_at = Time.current
      rows = query.rows
      Rails.cache.write(cache_key, {"computed_at" => computed_at, "rows" => rows}, expires_in: MAX_TTL)
      rows
    rescue ActiveRecord::ActiveRecordError => e
      if QueryService::CLICKHOUSE_FAILURES.keys.any? { e.message.include?(it) }
        Rails.cache.write(cache_key, {"error" => e.message}, expires_in: FAILURE_TTL)
      end

      raise
    end

    def cache_key
      @cache_key ||= [
        "attributed-usage",
        CACHE_KEY_VERSION,
        subscription.organization_id,
        subscription.id,
        Digest::SHA256.hexdigest(query.query)
      ].join("/")
    end
  end
end
