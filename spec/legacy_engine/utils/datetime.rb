# frozen_string_literal: true

# Vendored verbatim from app/services/utils/datetime.rb.
# Only `date_diff_with_timezone` is vendored: it is the single method the legacy
# billing-period engine reaches for, and Boundaries#billed_days depends on its
# exact ceil/offset semantics.
module LegacyEngine; end

module LegacyEngine::Utils
  class Datetime
    def self.date_diff_with_timezone(from_datetime, to_datetime, timezone)
      from = from_datetime
      from = Time.zone.parse(from.to_s) unless from.is_a?(ActiveSupport::TimeWithZone)

      to = to_datetime
      to = Time.zone.parse(to.to_s) unless to.is_a?(ActiveSupport::TimeWithZone)
      to_in_time = to.in_time_zone(timezone)
      to += 1.second if to_in_time == to_in_time.beginning_of_day # To make sure we do not miss a day

      from_offset = from.in_time_zone(timezone).utc_offset
      to_offset = to.in_time_zone(timezone).utc_offset
      offset = from_offset - to_offset

      (to - from - offset).fdiv(1.day).ceil
    end
  end
end
