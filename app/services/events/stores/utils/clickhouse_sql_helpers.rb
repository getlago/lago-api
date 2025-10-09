# frozen_string_literal: true

module Events
  module Stores
    module Utils
      module ClickhouseSqlHelpers
        # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
        #       Dates are in customer timezone to make sure the duration is good
        def self.duration_ratio_sql(from, to, duration, timezone)
          from_in_timezone = date_in_customer_timezone_sql(from, timezone)
          to_in_timezone = date_in_customer_timezone_sql(to, timezone)

          "(date_diff('days', #{from_in_timezone}, #{to_in_timezone}) + 1) / #{duration}"
        end

        def self.date_in_customer_timezone_sql(date_value, timezone)
          sql = if date_value.is_a?(String)
            # NOTE: date is a table field name, example: events_enriched.timestamp
            "toTimezone(#{date_value}, :timezone)"
          else
            "toTimezone(toDateTime64(:date, 5, 'UTC'), :timezone)"
          end

          ActiveRecord::Base.sanitize_sql_for_conditions(
            [sql, {date: date_value, timezone:}]
          )
        end
      end
    end
  end
end
