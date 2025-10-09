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

        def grouped_query(initial_values:)
          <<-SQL
            #{grouped_events_cte_sql(initial_values)}

            SELECT
              #{group_names},
              SUM(period_ratio) as aggregation
            FROM (
              SELECT
                #{group_names},
                (#{grouped_period_ratio_sql}) AS period_ratio
              FROM events_data
            ) cumulated_ratios
            GROUP BY #{group_names}
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

        delegate :charges_duration, :events_sql, :arel_table, :grouped_arel_columns, to: :store

        def events_cte_sql
          <<~SQL
            WITH events_data AS (
              (#{initial_value_sql})
              UNION ALL
              (#{
                events_sql(
                  ordered: true,
                  select: [
                    arel_table[:timestamp].as("timestamp"),
                    arel_table[:decimal_value].as("difference")
                  ]
                )
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
              -- NOTE: duration in seconds between current event and next one - or end of period if next event is null
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) > 0,

              -- NOTE: cumulative sum from previous events in the period
              (SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
              *
              -- NOTE: duration in seconds between current event and next one - or end of period if next event is null
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING))
              /
              -- NOTE: full duration of the period
              #{charges_duration.days.to_i}
              ,
              -- NOTE: duration was null so usage is null
              0
            )
          SQL
        end

        def grouped_events_cte_sql(initial_values)
          groups, _ = grouped_arel_columns

          <<-SQL
            WITH events_data AS (
              (#{grouped_initial_value_sql(initial_values)})
              UNION ALL
              (#{
                events_sql(
                  ordered: true,
                  select: groups + [
                    arel_table[:timestamp].as("timestamp"),
                    arel_table[:decimal_value].as("difference")
                  ]
                )
              })
              UNION ALL
              (#{grouped_end_of_period_value_sql(initial_values)})
            )
          SQL
        end

        def grouped_initial_value_sql(initial_values)
          values = initial_values.map do |initial_value|
            groups = store.grouped_by.map do |g|
              "'#{ActiveRecord::Base.sanitize_sql_for_conditions(initial_value[:groups][g])}'"
            end

            [
              groups,
              "toDateTime64(:from_datetime, 5, 'UTC')",
              "toDecimal128(#{initial_value[:value]}, :decimal_scale)"
            ].flatten.join(", ")
          end

          <<-SQL
            SELECT
              #{store.grouped_by.map.with_index { |_, index| "tuple.#{index + 1} AS g_#{index}" }.join(", ")},
              tuple.#{store.grouped_by.count + 1} AS timestamp,
              tuple.#{store.grouped_by.count + 2} AS difference
            FROM ( SELECT arrayJoin([#{values.map { "tuple(#{it})" }.join(", ")}]) AS tuple )
          SQL
        end

        def grouped_end_of_period_value_sql(initial_values)
          values = initial_values.map do |initial_value|
            groups = store.grouped_by.map do |g|
              "'#{ActiveRecord::Base.sanitize_sql_for_conditions(initial_value[:groups][g])}'"
            end

            [
              groups,
              "toDateTime64(:to_datetime, 5, 'UTC')",
              "toDecimal32(0, 0)"
            ].flatten.join(", ")
          end

          <<-SQL
            SELECT
              #{store.grouped_by.map.with_index { |_, index| "tuple.#{index + 1} AS g_#{index}" }.join(", ")},
              tuple.#{store.grouped_by.count + 1} AS timestamp,
              tuple.#{store.grouped_by.count + 2} AS difference
            FROM ( SELECT arrayJoin([#{values.map { "tuple(#{it})" }.join(", ")}]) AS tuple )
          SQL
        end

        def grouped_period_ratio_sql
          <<-SQL
            if(
              -- NOTE: duration in seconds between current event and next one - or end of period if next event is null
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (PARTITION BY #{group_names} ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) > 0,

              -- NOTE: cumulative sum from previous events in the period
              (SUM(difference) OVER (PARTITION BY #{group_names} ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
              *
              -- NOTE: duration in seconds between current event and next one - or end of period if next event is null
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (PARTITION BY #{group_names} ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING))
              /
              -- NOTE: full duration of the period
              #{charges_duration.days.to_i}
              ,
              -- NOTE: duration was null so usage is null
              0
            )
          SQL
        end

        def group_names
          @group_names ||= store.grouped_by.map.with_index { |_, index| "g_#{index}" }.join(", ")
        end
      end
    end
  end
end
