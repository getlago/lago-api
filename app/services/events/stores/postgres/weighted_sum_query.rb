# frozen_string_literal: true

module Events
  module Stores
    module Postgres
      class WeightedSumQuery
        def initialize(store:)
          @store = store
        end

        def query
          <<-SQL
            #{events_cte_sql}

            SELECT SUM(period_ratio) as aggregation
            FROM (
              SELECT (#{period_ratio_sql}) AS period_ratio
              FROM events_data
            ) cumulated_ratios
          SQL
        end

        # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
        def breakdown_query
          <<-SQL
            #{events_cte_sql}

            SELECT
              timestamp,
              difference,
              SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumul,
              EXTRACT(epoch FROM lead(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp) - timestamp) AS second_duration,
              (#{period_ratio_sql}) AS period_ratio
            FROM events_data
            ORDER BY timestamp ASC
          SQL
        end

        private

        attr_reader :store

        delegate :events, :charges_duration, :sanitized_propery_name, to: :store

        def events_cte_sql
          <<-SQL
            WITH events_data AS (
              (#{initial_value_sql})
              UNION
              (#{
                events
                  .select("timestamp, (#{sanitized_propery_name})::numeric AS difference, events.created_at")
                  .to_sql
              })
              UNION
              (#{end_of_period_value_sql})
            )
          SQL
        end

        def initial_value_sql
          <<-SQL
            SELECT *
            FROM (
              VALUES (timestamp without time zone :from_datetime, :initial_value, timestamp without time zone :from_datetime)
            ) AS t(timestamp, difference, created_at)
          SQL
        end

        def end_of_period_value_sql
          <<-SQL
            SELECT *
            FROM (
              VALUES (timestamp without time zone :to_datetime, 0, timestamp without time zone :to_datetime)
            ) AS t(timestamp, difference, created_at)
          SQL
        end

        def period_ratio_sql
          <<-SQL
            -- NOTE: duration in seconds between current event and next one
            CASE WHEN EXTRACT(EPOCH FROM LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp) - timestamp) = 0
            THEN
              0 -- NOTE: duration was null so usage is null
            ELSE
              -- NOTE: cumulative sum from previous events in the period
              (SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
              *
              -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
              EXTRACT(EPOCH FROM LEAD(timestamp, 1, :to_datetime) OVER (ORDER BY timestamp) - timestamp)
              /
              -- NOTE: full duration of the period
              #{charges_duration.days.to_i}
            END
          SQL
        end
      end
    end
  end
end
