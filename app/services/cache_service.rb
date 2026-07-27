# frozen_string_literal: true

class CacheService < BaseService
  # How long a boundary timestamp must have settled before the value computed at that boundary can
  # be cached. See #settled? for why an unsettled boundary cannot be cached at all.
  SETTLE_WINDOW = 1.second

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

    # Snapshot the time *before* computing, so an event enriched while the block runs is stamped
    # after the cache entry and invalidates it on the next read. Stamping after the block would
    # swallow every event ingested during the aggregation, which is the slow part.
    computed_at = Time.current

    value = yield

    # NOTE: It seems that passing expires_in: 0 is not a NO-OP, so bypass manually
    if (expires_in.nil? || expires_in > 0) && settled?(computed_at)
      Rails.cache.write(cache_key, wrap(value, computed_at), expires_in:)
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

  def wrap(value, computed_at)
    return value unless track_created_at?

    # cached_at is the moment the value was computed, never the timestamp of the last seen event.
    # Stamping it with invalidate_if_older_than would store the exact value the next read compares
    # against, so the entry would be discarded on every read and never serve.
    #
    # Keep sub-second precision: event timestamps carry milliseconds (ClickHouse enriched_at is
    # DateTime64(3)) or microseconds (Postgres). A bare iso8601 floors to whole seconds, so an
    # event enriched earlier in the same second as the computation would look newer than the entry
    # and wrongly recompute on every read, defeating the cache.
    {"cached_at" => computed_at.iso8601(6), "value" => value}
  end

  # An event enriched at the boundary timestamp may still be committing when the aggregation runs.
  # ClickHouse populates enriched_at with now(), which has one-second resolution, so such a sibling
  # is invisible to the invalidation: MAX(enriched_at) is byte-identical with or without it, and the
  # entry would keep serving usage that misses it. Refuse to cache until the boundary has settled.
  #
  # The window is measured from the pre-aggregation snapshot rather than Time.current, because what
  # matters is whether the boundary was already settled when the events were read, not how long the
  # aggregation happened to take afterwards.
  def settled?(computed_at)
    return true unless track_created_at?
    return true if invalidate_if_older_than.nil?

    invalidate_if_older_than < computed_at - SETTLE_WINDOW
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
