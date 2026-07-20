# frozen_string_literal: true

class CacheService < BaseService
  def initialize(*, expires_in: nil, invalidate_if_older_than: nil)
    @expires_in = expires_in
    @invalidate_if_older_than = invalidate_if_older_than
    super(nil)
  end

  def self.expire_cache(*, **)
    new(*, **).expire_cache
  end

  def cache_key
    raise NotImplementedError
  end

  def call(&)
    # NOTE: We don't rely on fetch here because some services compute expires_in = 0
    #       and we think this is the root of an invalid expiration time passed to Redis
    cached = Rails.cache.read(cache_key)
    return unwrap(cached) if cached && valid_cache?(cached)

    value = yield

    # NOTE: It seems that passing expires_in: 0 is not a NO-OP, so bypass manually
    if expires_in.nil? || expires_in > 0
      Rails.cache.write(cache_key, wrap(value), expires_in:)
    end

    value
  end

  def expire_cache
    Rails.cache.delete(cache_key)
  end

  private

  attr_reader :expires_in, :invalidate_if_older_than

  # Subclasses opting into lazy validation override this to wrap the stored value with its
  # creation time, so the cache can be invalidated at read time by comparing it against the
  # most recent event timestamp instead of relying on an external expiration.
  def track_created_at?
    false
  end

  def wrap(value)
    return value unless track_created_at?

    # Keep sub-second precision: event timestamps carry milliseconds (ClickHouse enriched_at is
    # DateTime64(3)) or microseconds (Postgres). A bare iso8601 floors to whole seconds, so a
    # re-read for the very same event would compare a floored cached_at against the unfloored
    # timestamp and wrongly recompute on every read, defeating the cache.
    cached_at = (invalidate_if_older_than || Time.current).iso8601(6)
    {"cached_at" => cached_at, "value" => value}
  end

  def unwrap(cached)
    return cached unless track_created_at?

    cached.is_a?(Hash) ? cached["value"] : cached
  end

  # Returns false when a more recent value is checked, forcing a recompute.
  # A legacy (unwrapped) entry is always considered stale so it gets rewritten.
  def valid_cache?(cached)
    return true unless track_created_at?
    return true if invalidate_if_older_than.nil?

    cached_at = cached.is_a?(Hash) ? cached["cached_at"] : nil
    return false if cached_at.nil?

    Time.iso8601(cached_at) >= invalidate_if_older_than
  end
end
