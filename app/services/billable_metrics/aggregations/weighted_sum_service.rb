# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        events = fetch_events(from_datetime:, to_datetime:)

        result.aggregation = compute_aggregation.ceil(20)
        result.count = events.count
        result.variation = events.sum("(#{sanitized_field_name})::numeric") || 0
        result.total_aggregated_units = result.variation

        if billable_metric.recurring?
          result.total_aggregated_units = latest_value + result.variation
          result.recurring_updated_at = events.last&.timestamp || from_datetime
        end

        result
      end

      private

      def fetch_events(from_datetime:, to_datetime:)
        events_scope(from_datetime:, to_datetime:).where("#{sanitized_field_name} IS NOT NULL")
      end

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
              fetch_events(from_datetime:, to_datetime:)
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
        initial_value = 0
        initial_value = latest_value if billable_metric.recurring?

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

      def latest_value
        quantified_events = QuantifiedEvent
          .where(billable_metric_id: billable_metric.id)
          .where(customer_id: subscription.customer_id)
          .where(external_subscription_id: subscription.external_id)
          .where(added_at: ...from_datetime)
          .order(added_at: :desc)

        quantified_events = quantified_events.where(group_id: group.id) if group

        quantified_event = quantified_events.first

        BigDecimal(quantified_event&.properties&.[](QuantifiedEvent::RECURRING_TOTAL_UNITS) || 0)
      end
    end
  end
end
