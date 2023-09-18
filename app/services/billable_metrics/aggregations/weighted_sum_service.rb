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

      def breakdown
        ActiveRecord::Base.connection.select_all(breakdown_sql).to_a
      end

      private

      def fetch_events(from_datetime:, to_datetime:)
        events_scope(from_datetime:, to_datetime:).where("#{sanitized_field_name} IS NOT NULL")
      end

      def compute_aggregation
        query_result = ActiveRecord::Base.connection.select_one(aggregation_sql)
        query_result['aggregation']
      end

      def aggregation_sql
        <<-SQL
          #{events_cte_sql}

          SELECT SUM(period_ratio) as aggregation
          FROM (
            SELECT (#{period_ratio_sql}) AS period_ratio
            FROM events_data
          ) cumulated_ratios
        SQL
      end

      def breakdown_sql
        <<-SQL
          #{events_cte_sql}

          SELECT
            timestamp,
            difference,
            SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul,
            EXTRACT(epoch FROM lead(timestamp, 1, '#{to_datetime.ceil}') OVER (ORDER BY timestamp) - timestamp) AS second_duration,
            (#{period_ratio_sql}) AS period_ratio
          FROM events_data
        SQL
      end

      def events_cte_sql
        <<-SQL
          WITH events_data AS (
            (#{initial_value_sql})
            UNION
            (#{
              fetch_events(from_datetime:, to_datetime:)
                .select("timestamp, (#{sanitized_field_name})::numeric AS difference, events.created_at")
                .to_sql
            })
            UNION
            (#{end_of_period_value_sql})
          )
        SQL
      end

      def initial_value_sql
        initial_value = 0
        initial_value = latest_value if billable_metric.recurring?

        <<-SQL
          SELECT *
          FROM (
            VALUES (timestamp without time zone '#{from_datetime}', #{initial_value}, timestamp without time zone '#{from_datetime}')
          ) AS t(timestamp, difference, created_at)
        SQL
      end

      def end_of_period_value_sql
        <<-SQL
          SELECT *
          FROM (
            VALUES (timestamp without time zone '#{to_datetime.ceil}', 0, timestamp without time zone '#{to_datetime.ceil}')
          ) AS t(timestamp, difference, created_at)
        SQL
      end

      def period_ratio_sql
        <<-SQL
          -- NOTE: duration in seconds between current event and next one
          CASE WHEN EXTRACT(EPOCH FROM LEAD(timestamp, 1, '#{to_datetime.ceil}') OVER (ORDER BY timestamp) - timestamp) = 0
          THEN
            0 -- NOTE: duration was null so usage is null
          ELSE
            -- NOTE: cumulative sum from previous events in the period
            (SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
            *
            -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
            EXTRACT(EPOCH FROM LEAD(timestamp, 1, '#{to_datetime.ceil}') OVER (ORDER BY timestamp) - timestamp)
            /
            -- NOTE: full duration of the period
            #{to_datetime.ceil - from_datetime}
          END
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
