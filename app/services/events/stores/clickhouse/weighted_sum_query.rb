# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      class WeightedSumQuery
        def initialize(store:)
          @store = store
        end

        def query
          <<-SQL
            #{events_cte_sql}

            SELECT sum(period_ratio) as aggregation
            FROM (
              SELECT (#{period_ratio_sql}) as period_ratio
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
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) AS second_duration,
              (#{period_ratio_sql}) AS period_ratio
            FROM events_data
            ORDER BY timestamp ASC
          SQL
        end

        private

        attr_reader :store

        delegate :events, :charges_duration, :sanitized_numeric_property, to: :store

        def events_cte_sql
          <<-SQL
            WITH events_data AS (
              (#{initial_value_sql})
              UNION ALL
              (#{
                events
                  .select("timestamp, #{sanitized_numeric_property} AS difference")
                  .group(Events::Stores::ClickhouseStore::DEDUPLICATION_GROUP)
                  .to_sql
              })
              UNION ALL
              (#{end_of_period_value_sql})
            )
          SQL
        end

        def initial_value_sql
          <<-SQL
            SELECT
              toDateTime64(:from_datetime, 5, 'UTC') as timestamp,
              toDecimal128(:initial_value, :decimal_scale) as difference
          SQL
        end

        def end_of_period_value_sql
          <<-SQL
            SELECT
              toDateTime64(:to_datetime, 5, 'UTC') as timestamp,
              toDecimal128(0, :decimal_scale) as difference
          SQL
        end

        def period_ratio_sql
          <<-SQL
            if(
              -- NOTE: duration in seconds between current event and next one
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) > 0,

              -- NOTE: cumulative sum from previous events in the period
              (SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
              *
              -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING))
              /
              -- NOTE: full duration of the period
              #{charges_duration.days.to_i}
              ,

              -- NOTE: duration was null so usage is null
              toDecimal128(0, :decimal_scale)
            )
          SQL
        end
      end
    end
  end
end
