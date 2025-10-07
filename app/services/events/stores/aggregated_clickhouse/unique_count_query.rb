# frozen_string_literal: true

module Events
  module Stores
    module AggregatedClickhouse
      class UniqueCountQuery
        def initialize(store:)
          @store = store
        end

        def query
          # NOTE: First sum calculates all operation values for a specific property
          # (for instance 2 relevant additions with 1 relevant removal [0, 1, 0, -1, 1] returns 1)
          # The next sum combines all properties into a single result
          <<-SQL
            #{events_cte_sql},
            event_values AS (
              SELECT
                property,
                SUM(adjusted_value) AS sum_adjusted_value
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{operation_value_sql(partition_by: %w[property])} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              GROUP BY property
            )

            SELECT coalesce(SUM(sum_adjusted_value), 0) AS aggregation FROM event_values
          SQL
        end

        def prorated_query
          <<-SQL
            #{events_cte_sql},
            event_values AS (
              SELECT
                property,
                operation_type,
                timestamp
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{operation_value_sql(partition_by: %w[property])} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, timestamp, operation_type
            ),
            cumulated_ratios AS (
              SELECT (#{period_ratio_sql(partition_by: %w[property])}) AS period_ratio
              FROM event_values
            )

            SELECT coalesce(SUM(period_ratio), 0) as aggregation
            FROM cumulated_ratios
          SQL
        end

        def grouped_query
          <<-SQL
            #{grouped_events_cte_sql},

            event_values AS (
              SELECT
                grouped_by,
                property,
                SUM(adjusted_value) AS sum_adjusted_value
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  grouped_by,
                  #{operation_value_sql(partition_by: %w[grouped_by property])} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              GROUP BY grouped_by, property
            )

            SELECT
              grouped_by::JSON,
              coalesce(SUM(sum_adjusted_value), 0) as aggregation
            FROM event_values
            GROUP BY grouped_by
          SQL
        end

        def grouped_prorated_query
          <<-SQL
            #{grouped_events_cte_sql},

            event_values AS (
              SELECT
                grouped_by,
                property,
                operation_type,
                timestamp
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  grouped_by,
                  #{operation_value_sql(partition_by: %w[grouped_by property])} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY grouped_by, property, operation_type, timestamp
            ),
            cumulated_ratios AS (
              SELECT
                (#{period_ratio_sql(partition_by: %w[grouped_by property])}) AS period_ratio,
                grouped_by
              FROM event_values
            )

            SELECT
              grouped_by::JSON,
              coalesce(SUM(period_ratio), 0) as aggregation
            FROM cumulated_ratios
            GROUP BY grouped_by
          SQL
        end

        # NOTE: Not used in production, only for debug purpose to check the computed values before aggregation
        # Returns an array of event's timestamp, property, operation type and operation value
        # Example:
        # [
        #   ["2023-03-16T00:00:00.000Z", "001", "add", 1],
        #   ["2023-03-17T00:00:00.000Z", "001", "add", 0],
        #   ["2023-03-17T10:00:00.000Z", "002", "remove", 0],
        #   ["2023-03-18T00:00:00.000Z", "001", "remove", -1],
        #   ["2023-03-19T00:00:00.000Z", "002", "add", 1]
        # ]
        def breakdown_query
          <<-SQL
            #{events_cte_sql}

            SELECT
              timestamp,
              property,
              operation_type,
              #{operation_value_sql(partition_by: %w[property])},
              lagInFrame(operation_type, 1) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)
            FROM events_data
            ORDER BY timestamp ASC, property ASC
          SQL
        end

        def prorated_breakdown_query(with_remove: false)
          <<-SQL
            #{events_cte_sql},
            event_values AS (
              SELECT
                property,
                operation_type,
                timestamp
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{operation_value_sql(partition_by: %w[property])} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, operation_type, timestamp
            )

            SELECT
              prorated_value,
              timestamp,
              property,
              operation_type
            FROM (
              SELECT
                (#{period_ratio_sql(partition_by: %w[property])}) AS prorated_value,
                timestamp,
                property,
                operation_type
              FROM event_values
            ) prorated_breakdown
            #{"WHERE prorated_value != 0" unless with_remove}
            ORDER BY timestamp ASC, property ASC
          SQL
        end

        private

        attr_reader :store

        delegate :charges_duration, :events_sql, :arel_enriched_table, :grouped_arel_columns, to: :store

        def events_cte_sql
          # NOTE: Common table expression returning event's timestamp, property name and operation type.
          <<-SQL
            WITH events_data AS (
              (#{
                events_sql(
                  ordered: true,
                  select: [
                    arel_enriched_table[:timestamp].as("timestamp"),
                    arel_enriched_table[:value].as("property"),
                    Arel::Nodes::NamedFunction.new(
                      "coalesce",
                      [
                        Arel::Nodes::NamedFunction.new("NULLIF", [
                          Arel::Nodes::SqlLiteral.new("events_enriched_expanded.sorted_properties['operation_type']"),
                          Arel::Nodes::SqlLiteral.new("''")
                        ]),
                        Arel::Nodes::SqlLiteral.new("'add'")
                      ]
                    ).as("operation_type")
                  ]
                )
              })
            )
          SQL
        end

        def grouped_events_cte_sql
          <<-SQL
            WITH events_data AS (#{
              events_sql(
                ordered: true,
                select: [
                  Arel::Nodes::NamedFunction.new(
                    "toJSONString",
                    [arel_enriched_table[:sorted_grouped_by]]
                  ).as("grouped_by"),
                  arel_enriched_table[:timestamp].as("timestamp"),
                  arel_enriched_table[:value].as("property"),
                  Arel::Nodes::NamedFunction.new(
                    "coalesce",
                    [
                      Arel::Nodes::NamedFunction.new("NULLIF", [
                        Arel::Nodes::SqlLiteral.new("events_enriched_expanded.sorted_properties['operation_type']"),
                        Arel::Nodes::SqlLiteral.new("''")
                      ]),
                      Arel::Nodes::SqlLiteral.new("'add'")
                    ]
                  ).as("operation_type")
                ]
              )
            })
          SQL
        end

        def operation_value_sql(partition_by:)
          partition = partition_by.join(", ")

          # NOTE: Returns 1 for relevant addition, -1 for relevant removal
          # If property already added, another addition returns 0 ; it returns 1 otherwise
          # If property already removed or not yet present, another removal returns 0 ; it returns -1 otherwise
          <<-SQL
            if (
              operation_type = 'add',
              (if(
                (lagInFrame(operation_type, 1) OVER (PARTITION BY #{partition} ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'add',
                toDecimal32(0, 0),
                toDecimal32(1, 0)
              ))
              ,
              (if(
                (lagInFrame(operation_type, 1, 'remove') OVER (PARTITION BY #{partition} ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'remove',
                toDecimal32(0, 0),
                toDecimal32(-1, 0)
              ))
            )
          SQL
        end

        def period_ratio_sql(partition_by:)
          partition = partition_by.join(", ")

          <<-SQL
            if(
              operation_type = 'add',
              (
                toDecimal64(
                  -- inclusive day count in customer TZ, same as PG
                  date_diff(
                    'days',
                    toDate(
                      toTimezone(
                        if(
                          timestamp < toDateTime64(:from_datetime, 3, 'UTC'),
                          toDateTime64(:from_datetime, 3, 'UTC'),
                          timestamp
                        ),
                        :timezone
                      )
                    ),
                    toDate(
                      toTimezone(
                        if(
                          -- if next event is before the period start, clamp to :from_datetime (no +1 day),
                          -- else add 1 day to make the range inclusive, just like PG does.
                          (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC'))
                            OVER (PARTITION BY #{partition} ORDER BY timestamp ASC
                              ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                          ) < toDateTime64(:from_datetime, 3, 'UTC'),
                          toDateTime64(:from_datetime, 3, 'UTC'),
                          addDays(
                            (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC'))
                              OVER (PARTITION BY #{partition} ORDER BY timestamp ASC
                                ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                            ),
                            1
                          )
                        ),
                        :timezone
                      )
                    )
                  ),
                :decimal_date_scale)
                / #{charges_duration || 1}
              ),
              0
            )
          SQL
        end
      end
    end
  end
end
