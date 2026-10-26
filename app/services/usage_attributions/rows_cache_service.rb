# frozen_string_literal: true

module UsageAttributions
  # Caches the rows of an attributed usage query under its SQL, so each level, filter, window and page
  # has its own entry, and a pricing change reads into a new one.
  #
  # An entry is served only while no event of the query was ingested after its watermark.
  # enriched_at is stamped when an insert begins, so the watermark trails the read by
  # INGESTION_MARGIN to cover rows that were not readable yet.
  class RowsCacheService < BaseService
    CACHE_KEY_VERSION = "1"
    INGESTION_MARGIN = 5.seconds
    MAX_TTL = 6.hours
    FAILURE_TTL = 10.seconds

    Result = BaseResult[:rows]

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
      entry = Rails.cache.read(cache_key)
      entry if entry && valid?(entry)
    end

    def valid?(entry)
      entry.key?("error") || !query.ingested_since?(entry["computed_at"] - INGESTION_MARGIN)
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
