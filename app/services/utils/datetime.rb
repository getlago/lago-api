# frozen_string_literal: true

module Utils
  class Datetime
    def self.valid_format?(datetime, format: :iso8601)
      return true if datetime.respond_to?(:strftime)
      return false unless datetime.is_a?(String)

      case format
      when :any
        Time.zone.parse(datetime).present?
      else
        Time.zone.iso8601(datetime).present?
      end
    rescue ArgumentError
      false
    end

    def self.future_date?(datetime)
      return true if datetime.is_a?(ActiveSupport::TimeWithZone) && datetime.future?
      return false unless valid_format?(datetime, format: :any)

      parsed_date = Time.zone.parse(datetime.to_s)
      parsed_date&.future? || false
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
