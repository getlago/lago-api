# frozen_string_literal: true

module Events
  module Stores
    module Concerns
      module ClickhouseSqlHelpers
        # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
        #       Dates are in customer timezone to make sure the duration is good
        def duration_ratio_sql(from, to, duration)
          from_in_timezone = date_in_customer_timezone_sql(from)
          to_in_timezone = date_in_customer_timezone_sql(to)

          "(date_diff('days', #{from_in_timezone}, #{to_in_timezone}) + 1) / #{duration}"
        end

        def date_in_customer_timezone_sql(date)
          sql = if date.is_a?(String)
            "toTimezone(#{date}, :timezone)"
          else
            "toTimezone(toDateTime64(:date, 5, 'UTC'), :timezone)"
          end

          ActiveRecord::Base.sanitize_sql_for_conditions(
            [sql, {date:, timezone: customer.applicable_timezone}]
          )
        end
      end
    end
  end
end
