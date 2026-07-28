# frozen_string_literal: true

class CacheService < BaseService
  # How long after latest event is enriched is needed to settle on Clickhouse side
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

    # Snapshot the time *before* computing, so the settle gate asks whether the boundary was already
    # settled when the events were read. Reading the clock after the block would let a slow
    # aggregation make a boundary that was hot at read time look settled by the time we write.
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
    # With no event seen yet there is no watermark to use, so fall back to the same conservative
    # bound the settle gate applies rather than to Time.current
    cached_at = (invalidate_if_older_than || computed_at - SETTLE_WINDOW).iso8601(6)
    {"cached_at" => cached_at, "value" => value}
  end

  # An event enriched at the boundary timestamp may still be committing when the aggregation runs.
  # ClickHouse stamps enriched_at with now64(3) when the insert *begins*, not when the row becomes
  # readable, so a sibling sharing that timestamp can land after the aggregation and stay invisible
  # to the invalidation: MAX(enriched_at) is unchanged with or without it, and the entry would keep
  # serving usage that misses it until the billing period ends. Refuse to cache a boundary that fresh.
  #
  # The window has to cover the insert-to-readable gap
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
