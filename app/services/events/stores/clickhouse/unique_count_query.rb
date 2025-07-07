# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
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
                  #{operation_value_sql} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC
              ) adjusted_event_values
              GROUP BY property
            )

            SELECT coalesce(SUM(sum_adjusted_value), 0) AS aggregation FROM event_values
          SQL
        end

        def prorated_query
          <<-SQL
            #{events_cte_sql},
            -- Check if next event on same day has opposite operation type so it nullifies this one at the same day
            same_day_ignored AS (
              SELECT
                e.property,
                e.operation_type,
                e.timestamp,
                CASE
                  WHEN next_event.next_property IS NOT NULL AND e.rn != 1
                  THEN true
                  ELSE false
                END AS is_ignored
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  ROW_NUMBER() OVER (PARTITION BY property ORDER BY timestamp) AS rn
                FROM events_data
                ORDER BY timestamp ASC
              ) as e
              LEFT JOIN (
                SELECT
                  timestamp as next_timestamp,
                  property as next_property,
                  operation_type as next_operation_type
                FROM events_data
              ) as next_event ON (
                next_event.next_property = e.property
                AND toDate(next_event.next_timestamp) = toDate(e.timestamp)
                AND next_event.next_operation_type != e.operation_type
                AND next_event.next_timestamp > e.timestamp
              )
            ),
            -- Check if the operation type is the same as previous, so it nullifies this one
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
                  #{operation_value_sql} AS adjusted_value
                FROM same_day_ignored
                WHERE is_ignored = false
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, operation_type, timestamp
            )

            SELECT coalesce(SUM(period_ratio), 0) as aggregation
            FROM (
              SELECT (#{period_ratio_sql}) AS period_ratio
              FROM event_values
            ) cumulated_ratios
          SQL
        end

        def grouped_query
          <<-SQL
            #{grouped_events_cte_sql},

            event_values AS (
              SELECT
                #{group_names.join(", ")},
                property,
                SUM(adjusted_value) AS sum_adjusted_value
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{group_names.join(", ")},
                  #{grouped_operation_value_sql} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC
              ) adjusted_event_values
              GROUP BY #{group_names.join(", ")}, property
            )

            SELECT
              #{group_names.join(", ")},
              coalesce(SUM(sum_adjusted_value), 0) as aggregation
            FROM event_values
            GROUP BY #{group_names.join(", ")}
          SQL
        end

        def grouped_prorated_query
          <<-SQL
            #{grouped_events_cte_sql},
            -- Check if next event on same day has opposite operation type so it nullifies this one at the same day
            same_day_ignored AS (
              SELECT
                e.#{group_names.join(", e.")},
                e.property,
                e.operation_type,
                e.timestamp,
                CASE
                  WHEN next_event.next_property IS NOT NULL AND e.rn != 1
                  THEN true
                  ELSE false
                END AS is_ignored
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{group_names.join(", ")},
                  ROW_NUMBER() OVER (PARTITION BY #{group_names.join(", ")}, property ORDER BY timestamp) AS rn
                FROM events_data
                ORDER BY timestamp ASC
              ) as e
              LEFT JOIN (
                SELECT
                  timestamp as next_timestamp,
                  property as next_property,
                  operation_type as next_operation_type,
                  #{group_names.map { |name| "#{name} as next_#{name}" }.join(", ")}
                FROM events_data
              ) as next_event ON (
                next_event.next_property = e.property
                AND #{group_names.map { |name| "next_event.next_#{name} = e.#{name}" }.join(" AND ")}
                AND toDate(next_event.next_timestamp) = toDate(e.timestamp)
                AND next_event.next_operation_type != e.operation_type
                AND next_event.next_timestamp > e.timestamp
              )
            ),
            -- Check if the operation type is the same as previous, so it nullifies this one
            event_values AS (
              SELECT
                #{group_names.join(", ")},
                property,
                operation_type,
                timestamp
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{group_names.join(", ")},
                  #{grouped_operation_value_sql} AS adjusted_value
                FROM same_day_ignored
                WHERE is_ignored = false
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY #{group_names.join(", ")}, property, operation_type, timestamp
            )

            SELECT
              #{group_names.join(", ")},
              coalesce(SUM(period_ratio), 0) as aggregation
            FROM (
              SELECT
                (#{grouped_period_ratio_sql}) AS period_ratio,
                #{group_names.join(", ")}
              FROM event_values
            ) cumulated_ratios
            GROUP BY #{group_names.join(", ")}
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
              #{operation_value_sql},
              anyOrNull(operation_type) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)
            FROM events_data
            ORDER BY timestamp ASC
          SQL
        end

        def prorated_breakdown_query(with_remove: false)
          <<-SQL
            #{events_cte_sql},
            -- Check if next event on same day has opposite operation type so it nullifies this one at the same day
            same_day_ignored AS (
              SELECT
                e.property,
                e.operation_type,
                e.timestamp,
                CASE
                  WHEN next_event.next_property IS NOT NULL AND e.rn != 1
                  THEN true
                  ELSE false
                END AS is_ignored
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  ROW_NUMBER() OVER (PARTITION BY property ORDER BY timestamp) AS rn
                FROM events_data
                ORDER BY timestamp ASC
              ) as e
              LEFT JOIN (
                SELECT
                  timestamp as next_timestamp,
                  property as next_property,
                  operation_type as next_operation_type
                FROM events_data
              ) as next_event ON (
                next_event.next_property = e.property
                AND toDate(next_event.next_timestamp) = toDate(e.timestamp)
                AND next_event.next_operation_type != e.operation_type
                AND next_event.next_timestamp > e.timestamp
              )
            ),
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
                  #{operation_value_sql} AS adjusted_value
                FROM same_day_ignored
                WHERE is_ignored = false
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, timestamp, operation_type
            )

            SELECT
              prorated_value,
              timestamp,
              property,
              operation_type
            FROM (
              SELECT
                (#{period_ratio_sql}) AS prorated_value,
                timestamp,
                property,
                operation_type
              FROM event_values
            ) prorated_breakdown
            #{"WHERE prorated_value != 0" unless with_remove}
            ORDER BY timestamp ASC
          SQL
        end

        private

        attr_reader :store

        delegate :charges_duration, :events_sql, :arel_table, :grouped_arel_columns, to: :store

        def events_cte_sql
          # NOTE: Common table expression returning event's timestamp, property name and operation type.
          <<-SQL
            WITH events_data AS (
              (#{
                events_sql(
                  ordered: true,
                  select: [
                    arel_table[:timestamp].as("timestamp"),
                    arel_table[:value].as("property"),
                    Arel::Nodes::NamedFunction.new(
                      "coalesce",
                      [
                        Arel::Nodes::NamedFunction.new("NULLIF", [
                          Arel::Nodes::SqlLiteral.new("events_enriched.sorted_properties['operation_type']"),
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
          groups, _ = grouped_arel_columns

          <<-SQL
            WITH events_data AS (#{
              events_sql(
                ordered: true,
                select: groups + [
                  arel_table[:timestamp].as("timestamp"),
                  arel_table[:value].as("property"),
                  Arel::Nodes::NamedFunction.new(
                    "coalesce",
                    [
                      Arel::Nodes::NamedFunction.new("NULLIF", [
                        Arel::Nodes::SqlLiteral.new("events_enriched.sorted_properties['operation_type']"),
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

        def operation_value_sql
          # NOTE: Returns 1 for relevant addition, -1 for relevant removal
          # If property already added, another addition returns 0 ; it returns 1 otherwise
          # If property already removed or not yet present, another removal returns 0 ; it returns -1 otherwise
          <<-SQL
            if (
              operation_type = 'add',
              (if(
                (anyOrNull(operation_type) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'add',
                toDecimal128(0, :decimal_scale),
                toDecimal128(1, :decimal_scale)
              ))
              ,
              (if(
                (anyOrNull(operation_type) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'remove',
                toDecimal128(0, :decimal_scale),
                toDecimal128(-1, :decimal_scale)
              ))
            )
          SQL
        end

        def grouped_operation_value_sql
          # NOTE: Returns 1 for relevant addition, -1 for relevant removal
          # If property already added, another addition returns 0 ; it returns 1 otherwise
          # If property already removed or not yet present, another removal returns 0 ; it returns -1 otherwise
          <<-SQL
            if (
              operation_type = 'add',
              (if(
                (anyOrNull(operation_type) OVER (PARTITION BY #{group_names.join(", ")}, property ORDER BY timestamp ASC ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'add',
                toDecimal128(0, :decimal_scale),
                toDecimal128(1, :decimal_scale)
              ))
              ,
              (if(
                (anyOrNull(operation_type) OVER (PARTITION BY #{group_names.join(", ")}, property ORDER BY timestamp ASC ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'remove',
                toDecimal128(0, :decimal_scale),
                toDecimal128(-1, :decimal_scale)
              ))
            )
          SQL
        end

        def period_ratio_sql
          <<-SQL
            toDecimal128(
              if(
                operation_type = 'add',
                -- NOTE: duration in full days between current add and next remove - using end of period as final boundaries if no remove
                ceil(
                  date_diff(
                    'seconds',
                    if(timestamp < toDateTime64(:from_datetime, 3, 'UTC'), toDateTime64(:from_datetime, 3, 'UTC'), timestamp),
                    if(
                      (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC')) OVER (PARTITION BY property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) < toDateTime64(:from_datetime, 3, 'UTC'),
                      toDateTime64(:from_datetime, 3, 'UTC'),
                      leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC')) OVER (PARTITION BY property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                    ),
                    :timezone
                  ) / 86400
                )
                /
                -- NOTE: full duration of the period
                #{charges_duration || 1},

                -- NOTE: operation was a remove, so the duration is 0
                0
              ),
              :decimal_scale
            )
          SQL
        end

        def grouped_period_ratio_sql
          <<-SQL
            toDecimal128(
              if(
                operation_type = 'add',
                -- NOTE: duration in full days between current add and next remove - using end of period as final boundaries if no remove
                ceil(
                  date_diff(
                    'seconds',
                    if(timestamp < toDateTime64(:from_datetime, 3, 'UTC'), toDateTime64(:from_datetime, 3, 'UTC'), timestamp),
                                          if(
                        (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC')) OVER (PARTITION BY #{group_names.join(", ")}, property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) < toDateTime64(:from_datetime, 3, 'UTC'),
                        toDateTime64(:to_datetime, 3, 'UTC'),
                        leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC')) OVER (PARTITION BY #{group_names.join(", ")}, property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                      ),
                    :timezone
                  ) / 86400
                )
                /
                -- NOTE: full duration of the period
                #{charges_duration || 1},

                -- NOTE: operation was a remove, so the duration is 0
                0
              ),
              :decimal_scale
            )
          SQL
        end

        def group_names
          @group_names ||= store.grouped_by.map.with_index { |_, index| "g_#{index}" }
        end
      end
    end
  end
end
