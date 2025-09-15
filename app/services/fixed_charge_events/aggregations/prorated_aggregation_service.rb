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

        result["aggregation"]
      end

      private

      def prorated_query
        <<-SQL
          #{fixed_charge_events_cte_sql}

          SELECT COALESCE(SUM(weighted_units), 0) as aggregation
          FROM (
            SELECT (#{period_ratio_sql} * units) AS weighted_units
            FROM fixed_charge_events_data
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
                units"
              ).to_sql
          })
        SQL
      end

      def period_ratio_sql
        <<-SQL
          (
            (
              -- define the end of the period
              DATE((
                -- NOTE: if following event is older than the start of the period, we use the start of the period as the reference
                CASE WHEN (LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp)) < :from_datetime
                THEN :from_datetime
                ELSE LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp)
                END
              )::timestamptz AT TIME ZONE :timezone)
              -- define the start of the period
              - DATE((
                -- NOTE: if events is older than the start of the period, we use the start of the period as the reference
                CASE WHEN timestamp < :from_datetime THEN :from_datetime ELSE timestamp END
              )::timestamptz AT TIME ZONE :timezone)
            )::numeric
          )
          /
          -- NOTE: full duration of the period
          #{charges_duration || 1}::numeric
        SQL
      end
    end
  end
end


        