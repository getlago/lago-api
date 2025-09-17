# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class ProratedAggregationService < BaseService
      def call
        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            prorated_query,
            {
              from_datetime:,
              to_datetime:,
              timezone: customer.applicable_timezone
            }
          ]
        )
        result = ActiveRecord::Base.connection.select_one(sql)
        result.aggregation = result["aggregation"]
        result
      end

      private

      def prorated_query
        <<-SQL
          #{fixed_charge_events_cte_sql},
          fixed_charge_events_ignored AS (
            SELECT * FROM (
              SELECT *,
                CASE WHEN #{later_event_earlier_timestamp_sql} THEN true ELSE false END as is_ignored_event
              FROM fixed_charge_events_data
            ) cumulated_ratios
            WHERE is_ignored_event = false
          )

          SELECT COALESCE(SUM(weighted_units), 0) AS aggregation
          FROM (
            SELECT CASE WHEN (#{period_ratio_sql} * units) < 0 THEN 0 ELSE (#{period_ratio_sql} * units) END AS weighted_units
            FROM fixed_charge_events_ignored
          ) cumulated_ratios
        SQL
      end

      def debug_query
        <<-SQL
          #{fixed_charge_events_cte_sql},
          fixed_charge_events_ignored AS (
            SELECT * FROM (
              SELECT *,
                CASE WHEN #{later_event_earlier_timestamp_sql} THEN true ELSE false END as is_ignored_event
              FROM fixed_charge_events_data
            ) cumulated_ratios
            WHERE is_ignored_event = false
          )

          SELECT weighted_units, period_start, period_end, units
          FROM (
            SELECT CASE WHEN (#{period_ratio_sql} * units) < 0 THEN 0 ELSE (#{period_ratio_sql} * units) END AS weighted_units,
              #{period_start} AS period_start,
              #{period_end} AS period_end,
              units
            FROM fixed_charge_events_ignored
          ) cumulated_ratios
        SQL
      end

      def fixed_charge_events_cte_sql
        # NOTE: Common table expression returning event's timestamp, units
        <<-SQL
          WITH fixed_charge_events_data AS (#{
            events_in_range
              .select(
                "timestamp, \
                created_at, \
                units"
              ).to_sql
          })
        SQL
      end

      def later_event_earlier_timestamp_sql
        <<-SQL
          (
            SELECT
              1
            FROM fixed_charge_events_data next_event
            WHERE next_event.timestamp < fixed_charge_events_data.timestamp
              AND next_event.created_at > fixed_charge_events_data.created_at
            LIMIT 1
          ) = 1
        SQL
      end

      def period_ratio_sql
        <<-SQL
          (
            (
              -- define the end of the period
              #{period_end}
              -- define the start of the period
              - #{period_start}
            )::numeric
          )
          /
          -- NOTE: full duration of the period
          #{charges_duration || 1}::numeric
        SQL
      end

      def period_end
        <<-SQL
          DATE((
            -- NOTE: if following event is older than the start of the period, we use the start of the period as the reference
            CASE WHEN (LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY created_at)) < :from_datetime
            THEN :from_datetime
            ELSE LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY created_at)
            END
          )::timestamptz AT TIME ZONE :timezone)
        SQL
      end

      def period_start
        <<-SQL
          DATE((
            -- NOTE: if events is older than the start of the period, we use the start of the period as the reference
            CASE WHEN timestamp < :from_datetime THEN :from_datetime ELSE timestamp END
          )::timestamptz AT TIME ZONE :timezone)
        SQL
      end
    end
  end
end
