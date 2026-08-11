# frozen_string_literal: true

module Events
  # Caches the property combinations seen for one billable metric code over one window, as computed
  # by Events::Stores::BaseStore#distinct_codes_and_property_combinations.
  #
  # The combinations can only change when an event is ingested for that code, so the entry is
  # validated lazily against the code's last_seen_at watermark rather than expired on reception.
  #
  # The stored value is an array of [properties, last_seen_at_iso8601] pairs, kept JSON-safe so it
  # survives the cache store round-trip regardless of the configured coder.
  class PeriodCombinationsCacheService < CacheService
    # IMPORTANT
    # when changing the stored value shape, bump this so old values are immediately invalidated!
    CACHE_KEY_VERSION = "1"

    def initialize(subscription:, code:, filter_keys:, from_datetime:, to_datetime:, expires_in: nil,
      invalidate_if_older_than: nil)
      @subscription = subscription
      @code = code
      @filter_keys = filter_keys
      @from_datetime = from_datetime
      @to_datetime = to_datetime

      super(expires_in:, invalidate_if_older_than:)
    end

    # from_datetime is nil for recurring metrics, whose combinations are read over the whole history.
    # The filter keys are part of the key because they decide which properties the combinations hold,
    # so adding or removing a filter on the billable metric invalidates the entry.
    def cache_key
      [
        "period-combinations",
        CACHE_KEY_VERSION,
        subscription.id,
        code,
        from_datetime&.iso8601 || "all",
        to_datetime.iso8601,
        Digest::SHA256.hexdigest(filter_keys.sort.join(","))[0, 12]
      ].join("/")
    end

    private

    attr_reader :subscription, :code, :filter_keys, :from_datetime, :to_datetime

    # The value is only meaningful together with the watermark it was computed at, so this service
    # always stores the wrapped shape.
    def track_created_at?
      true
    end
  end
end
