# frozen_string_literal: true

module Events
  module Stores
    module Utils
      module ClickhouseSqlHelpers
        DECIMAL_SCALE = 26
        DECIMAL_DATE_SCALE = 10

        # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
        #       Dates are in customer timezone to make sure the duration is good
        def duration_ratio_sql(from, to, duration, timezone)
          from_in_timezone = date_in_customer_timezone_sql(from, timezone)
          to_in_timezone = date_in_customer_timezone_sql(to, timezone)

          "(date_diff('days', #{from_in_timezone}, #{to_in_timezone}) + 1) / #{duration}"
        end

        def date_in_customer_timezone_sql(date_value, timezone)
          sql = if date_value.is_a?(String)
            # NOTE: date is a table field name, example: events_enriched.timestamp
            "toTimezone(#{date_value}, :timezone)"
          else
            "toTimezone(toDateTime64(:date, 5, 'UTC'), :timezone)"
          end

          sanitize_clickhouse_sql([sql, {date: date_value, timezone:}])
        end

        # NOTE: ClickHouse reads a backslash inside a string literal as an escape character, which the
        #       PostgreSQL quoting of `ActiveRecord::Base.sanitize_sql_for_conditions` leaves alone: a value
        #       ending with one escapes its closing quote. Values are quoted by the ClickHouse adapter instead,
        #       except times, which it renders without their fractional seconds.
        def sanitize_clickhouse_sql(statement)
          template, *values = statement

          ::Clickhouse::BaseRecord.sanitize_sql_for_conditions([template, *values.map { clickhouse_bind_value(it) }])
        end

        def clickhouse_bind_value(value)
          case value
          when Array then value.map { clickhouse_bind_value(it) }
          when Hash then value.transform_values { clickhouse_bind_value(it) }
          when Time, DateTime, ActiveSupport::TimeWithZone then ActiveRecord::Base.with_connection { it.quoted_date(value) }
          else value
          end
        end

        def quote(value)
          ::Clickhouse::BaseRecord.connection.quote(value)
        end

        # NOTE: A numeric literal containing a decimal point (e.g. 2500.0) is parsed as a Float64 by
        #       ClickHouse and loses precision when cast to Decimal. Rendering the value as a
        #       fixed-point string makes toDecimalXX read an exact decimal literal instead.
        def decimal_literal(value)
          BigDecimal(value.to_s).to_s("F")
        end

        def sql_condition(template, *values)
          sanitize_clickhouse_sql([template, *values])
        end

        # When the boundary is the pay-in-advance event's own timestamp, tie-break events
        # sharing it by transaction_id so each gets a distinct position instead of all being
        # priced as the batch's last unit. transaction_id trails every events sort key, so
        # the comparison stays index-aligned. Any other boundary keeps the plain <=.
        def upper_timestamp_boundary_sql(to_datetime, prefix: "")
          boundary_transaction_id = (filters[:event]&.transaction_id if to_datetime == boundaries[:max_timestamp])

          if boundary_transaction_id
            sql_condition(
              "(#{prefix}timestamp < ? OR (#{prefix}timestamp = ? AND #{prefix}transaction_id <= ?))",
              to_datetime,
              to_datetime,
              boundary_transaction_id
            )
          else
            sql_condition("#{prefix}timestamp <= ?", to_datetime)
          end
        end
      end
    end
  end
end
