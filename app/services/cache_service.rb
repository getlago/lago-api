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

    # cached_at is a watermark of what the value aggregated, not a wall clock reading. It must stay
    # the last seen event timestamp so that *any* event above it invalidates the entry.
    #
    # Stamping Time.current instead would open a hole: ClickHouse fills enriched_at with now(),
    # which floors to the second, so an event inserted at 05:31:15.6 is recorded as 05:31:15.000 -
    # earlier than a snapshot taken at 05:31:15.400. An event that landed after the aggregation
    # would then compare as already covered, and the entry would serve usage that misses it for the
    # rest of the billing period. Comparing a precise clock against a floored one is unsound.
    #
    # Keep sub-second precision: event timestamps carry milliseconds (ClickHouse enriched_at is
    # DateTime64(3)) or microseconds (Postgres), and a bare iso8601 would floor them.
    #
    # With no event seen yet, fall back to the conservative bound the settle gate already used,
    # never to Time.current, for the same reason.
    cached_at = (invalidate_if_older_than || computed_at - SETTLE_WINDOW).iso8601(6)
    {"cached_at" => cached_at, "value" => value}
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
