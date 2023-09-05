# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        result.aggregation = compute_aggregation
        result.current_usage_units = 0
        result.count = 0
        result.pay_in_advance_aggregation = BigDecimal(0)
        result.options = { running_total: 0 }
        result
      end

      private

      def compute_aggregation
        # query_result = ActiveRecord::Base.connection.select_all(aggregation_sql)
        # query_result

        # byebug

        query_result = ActiveRecord::Base.connection.select_one(aggregation_sql)
        query_result['aggregation']
      end

      def aggregation_sql
        <<-SQL
          WITH events_data AS (
            (#{initial_value})
            UNION
            (#{
              events_scope(from_datetime:, to_datetime:)
                .select("timestamp, (#{sanitized_field_name})::numeric AS difference")
                .to_sql
            })
            UNION
            (#{end_of_period_value})
          )

          SELECT SUM(period_ratio) as aggregation
          FROM (
            SELECT
              -- TODO: remove when finished
              timestamp,
              difference,
              sum(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumul,
              EXTRACT(epoch FROM lead(timestamp, 1, '#{to_datetime}') OVER (ORDER BY timestamp) - timestamp) AS second_duration,
              --

            (
              -- NOTE: duration in seconds between current event and next one
              -- TODO: takes weighted interval into account (+ group per interval in CTE ??)
              CASE WHEN EXTRACT(EPOCH FROM LEAD(timestamp, 1, '#{to_datetime}') OVER (ORDER BY timestamp) - timestamp) = 0
              THEN
                0 -- NOTE: duration was null so usage is null
              ELSE
                -- NOTE: cumulative sum from previous events in the period
                (sum(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
                /
                -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
                EXTRACT(EPOCH FROM LEAD(timestamp, 1, '#{to_datetime}') OVER (ORDER BY timestamp) - timestamp)
              END
            ) AS period_ratio
            FROM events_data
          ) cumulated_ratios
        SQL
      end

      def initial_value
        initial_value = 0 # TODO: when recurring, get last cumul

        <<-SQL
          SELECT *
          FROM (
            VALUES (timestamp without time zone '#{from_datetime}', #{initial_value})
          ) AS t(timestamp, difference)
        SQL
      end

      def end_of_period_value
        <<-SQL
          SELECT *
          FROM (
            VALUES (timestamp without time zone '#{to_datetime}', 0)
          ) AS t(timestamp, difference)
        SQL
      end
    end
  end
end
