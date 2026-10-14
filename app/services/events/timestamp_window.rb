# frozen_string_literal: true

module Events
  # Event timestamps must fall in a range both event stores can hold. On top of that, an
  # installation can refuse events too far in the past or the future (for example a timestamp
  # sent in milliseconds instead of seconds) with LAGO_EVENTS_MAX_PAST_DAYS and
  # LAGO_EVENTS_MAX_FUTURE_HOURS. Both are off when unset.
  module TimestampWindow
    EARLIEST = Time.utc(1970, 1, 1)
    # ClickHouse DateTime64 stops at the end of 2299.
    LATEST = Time.utc(2300, 1, 1)

    # Read once at boot: the check runs for every ingested event.
    MAX_PAST_DAYS = ENV["LAGO_EVENTS_MAX_PAST_DAYS"].presence&.to_i
    MAX_FUTURE_HOURS = ENV["LAGO_EVENTS_MAX_FUTURE_HOURS"].presence&.to_i

    module_function

    def within?(timestamp, now: Time.current)
      return false if timestamp < EARLIEST || timestamp >= LATEST

      return false if MAX_PAST_DAYS && timestamp < now - MAX_PAST_DAYS.days
      return false if MAX_FUTURE_HOURS && timestamp > now + MAX_FUTURE_HOURS.hours

      true
    end
  end
end
