# frozen_string_literal: true

module Utils
  class Datetime
    def self.valid_format?(datetime)
      datetime.respond_to?(:strftime) || datetime.is_a?(String) && DateTime._strptime(datetime).present?
    end

    def self.date_diff_with_timezone(from_datetime, to_datetime, timezone)
      from = from_datetime
      from = Time.zone.parse(from.to_s) unless from.is_a?(ActiveSupport::TimeWithZone)

      to = to_datetime
      to = Time.zone.parse(to.to_s) unless to.is_a?(ActiveSupport::TimeWithZone)
      to += 1.second if to == to.beginning_of_day # To make sure we do not miss a day

      from_offset = from.in_time_zone(timezone).utc_offset
      to_offset = to.in_time_zone(timezone).utc_offset
      offset = from_offset - to_offset

      (to - from - offset).fdiv(1.day).ceil
    end
  end
end
