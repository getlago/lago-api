# frozen_string_literal: true

module Utils
  class DatetimeService < BaseService
    def self.valid_format?(datetime)
      datetime.respond_to?(:strftime) || datetime.is_a?(String) && DateTime._strptime(datetime).present?
    end

    def self.date_diff_with_timezone(from_datetime, to_datetime, timezone)
      from = from_datetime
      from = Time.zone.parse(from.to_s) unless from.is_a?(ActiveSupport::TimeWithZone)

      to = to_datetime
      to = Time.zone.parse(to.to_s) unless to.is_a?(ActiveSupport::TimeWithZone)

      from_offset = from.in_time_zone(timezone).utc_offset
      to_offset = to.in_time_zone(timezone).utc_offset
      offset = from_offset - to_offset

      (to - from - offset).fdiv(1.day).ceil
    end

    def self.period_total_length_in_days(from_datetime, to_datetime, interval)
      timezone = from_datetime.time_zone

      case interval.to_sym
      when :weekly
        7
      when :monthly
        Utils::DatetimeService.date_diff_with_timezone(
          from_datetime.beginning_of_month.in_time_zone,
          to_datetime.end_of_month.in_time_zone,
          timezone,
        )
      when :quarterly
        Utils::DatetimeService.date_diff_with_timezone(
          from_datetime.beginning_of_quarter.in_time_zone,
          to_datetime.end_of_quarter.in_time_zone,
          timezone,
        )
      when :yearly
        Utils::DatetimeService.date_diff_with_timezone(
          from_datetime.beginning_of_year.in_time_zone,
          to_datetime.end_of_year.in_time_zone,
          timezone,
        )
      end
    end
  end
end
