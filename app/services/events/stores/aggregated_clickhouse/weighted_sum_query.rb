# frozen_string_literal: true

module Events
  module Stores
    module AggregatedClickhouse
      class WeightedSumQuery
        def initialize(store:)
          @store = store
        end

        def query
          <<-SQL
            #{events_cte_sql},
            cumulated_ratios AS (
              SELECT (#{period_ratio_sql}) as period_ratio
              FROM events_data
            )

            SELECT sum(period_ratio) as aggregation
            FROM cumulated_ratios
          SQL
        end

        def grouped_query(initial_values:)
          <<-SQL
            #{grouped_events_cte_sql(initial_values)},
            cumulated_ratios AS (
              SELECT
                grouped_by,
                (#{grouped_period_ratio_sql}) AS period_ratio
              FROM events_data
            )

            SELECT
              grouped_by::JSON,
              SUM(period_ratio) as aggregation
            FROM cumulated_ratios
            GROUP BY grouped_by
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
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING))::INT AS second_duration,
              (#{period_ratio_sql}) AS period_ratio
            FROM events_data
            ORDER BY timestamp ASC
          SQL
        end

        private

        attr_reader :store

        delegate :charges_duration, :events_sql, :arel_enriched_table, :grouped_arel_columns, to: :store

        def events_cte_sql
          <<~SQL
            WITH events_data AS (
              (#{initial_value_sql})
              UNION ALL
              (#{
                events_sql(
                  ordered: true,
                  select: [
                    arel_enriched_table[:timestamp].as("timestamp"),
                    arel_enriched_table[:decimal_value].as("difference")
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
              -- NOTE: duration in seconds between current event and next one
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) > 0,

              -- NOTE: cumulative sum from previous events in the period
              (SUM(difference) OVER (ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
              *
              -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING))
              /
              -- NOTE: full duration of the period
              #{charges_duration.days.to_i},
              -- NOTE: duration was null so usage is null
              0
            )
          SQL
        end

        def grouped_events_cte_sql(initial_values)
          <<-SQL
            WITH events_data AS (
              (#{grouped_initial_value_sql(initial_values)})
              UNION ALL
              (#{
                events_sql(
                  ordered: true,
                  select: [
                    Arel::Nodes::NamedFunction.new(
                      "toJSONString",
                      [arel_enriched_table[:sorted_grouped_by]]
                    ).as("grouped_by"),
                    arel_enriched_table[:timestamp].as("timestamp"),
                    arel_enriched_table[:decimal_value].as("difference")
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
            [
              sanitized_values(formated_groups_values(initial_value)),
              "toDateTime64(:from_datetime, 5, 'UTC')",
              "toDecimal128(#{initial_value[:value]}, :decimal_scale)"
            ].join(", ")
          end

          tuple_select_sql(values)
        end

        def grouped_end_of_period_value_sql(initial_values)
          values = initial_values.map do |initial_value|
            [
              sanitized_values(formated_groups_values(initial_value)),
              "toDateTime64(:to_datetime, 5, 'UTC')",
              "toDecimal32(0, 0)"
            ].join(", ")
          end

          tuple_select_sql(values)
        end

        def grouped_period_ratio_sql
          <<-SQL
            if(
              -- NOTE: duration in seconds between current event and next one
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (PARTITION BY grouped_by ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) > 0,

              -- NOTE: cumulative sum from previous events in the period
              (SUM(difference) OVER (PARTITION BY grouped_by ORDER BY timestamp ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW))
              *
              -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
              date_diff('seconds', timestamp, leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 5, 'UTC')) OVER (PARTITION BY grouped_by ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING))
              /
              -- NOTE: full duration of the period
              #{charges_duration.days.to_i},
              -- NOTE: duration was null so usage is null
              0
            )
          SQL
        end

        def formated_groups_values(initial_value)
          store.grouped_by
            .index_with { initial_value[:groups][it] || store.class::NIL_GROUP_VALUE }
            .sort_by { |key, _| key }
            .to_h
            .to_json(escape_html_entities: false)
        end

        def tuple_select_sql(values)
          <<-SQL
            SELECT
              tuple.1 AS grouped_by,
              tuple.2 AS timestamp,
              tuple.3 AS difference
            FROM ( SELECT arrayJoin([#{values.map { "tuple(#{it})" }.join(", ")}]) AS tuple )
          SQL
        end

        def sanitized_values(value)
          ActiveRecord::Base.sanitize_sql_for_conditions(
            ["?", value]
          )
        end
      end
    end
  end
end
