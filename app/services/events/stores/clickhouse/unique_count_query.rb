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
            event_values AS (
              SELECT
                property,
                operation_type,
                timestamp,
                ROW_NUMBER() OVER (PARTITION BY property ORDER BY timestamp) AS rn
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{operation_value_sql} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, timestamp, operation_type
            ),
            events_with_next AS (
              SELECT
                e1.property,
                e1.operation_type,
                e1.timestamp,
                e1.rn,
                e2.operation_type AS next_operation_type,
                e2.timestamp AS next_timestamp
              FROM event_values e1
              LEFT JOIN event_values e2 ON e1.property = e2.property AND toInt64(e1.rn) = toInt64(e2.rn) - 1
            ),
            events_with_prev AS (
              SELECT
                e1.property,
                e1.operation_type,
                e1.timestamp,
                e1.rn,
                e1.next_operation_type,
                e1.next_timestamp,
                e2.operation_type AS prev_operation_type
              FROM events_with_next e1
              LEFT JOIN event_values e2 ON e1.property = e2.property AND toInt64(e1.rn) = toInt64(e2.rn) + 1
            ),
            events_filtered AS (
              SELECT
                property,
                operation_type,
                timestamp,
                rn,
                -- Check if current event should be ignored
                if(
                  -- Check if next event on same day has opposite operation type
                  (rn != 1 AND toDate(next_timestamp) = toDate(timestamp) AND next_operation_type != operation_type)
                  OR
                  -- Check if previous event has same operation type
                  prev_operation_type = operation_type,
                  true,
                  false
                ) AS is_ignored
              FROM events_with_prev
            )

            SELECT coalesce(SUM(period_ratio), 0) as aggregation
            FROM (
              SELECT (#{period_ratio_sql}) AS period_ratio
              FROM events_filtered
              WHERE is_ignored = false
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

            event_values AS (
              SELECT
                #{group_names.join(", ")},
                property,
                operation_type,
                timestamp,
                ROW_NUMBER() OVER (PARTITION BY #{group_names.join(", ")}, property ORDER BY timestamp) AS rn
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
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY #{group_names.join(", ")}, property, operation_type, timestamp
            ),
            events_with_next AS (
              SELECT
                e1.#{group_names.join(", e1.")},
                e1.property,
                e1.operation_type,
                e1.timestamp,
                e1.rn,
                e2.operation_type AS next_operation_type,
                e2.timestamp AS next_timestamp
              FROM event_values e1
              LEFT JOIN event_values e2 ON e1.property = e2.property AND toInt64(e1.rn) = toInt64(e2.rn) - 1 AND #{group_names.map { |name| "e1.#{name} = e2.#{name}" }.join(" AND ")}
            ),
            events_with_prev AS (
              SELECT
                e1.#{group_names.join(", e1.")},
                e1.property,
                e1.operation_type,
                e1.timestamp,
                e1.rn,
                e1.next_operation_type,
                e1.next_timestamp,
                e2.operation_type AS prev_operation_type
              FROM events_with_next e1
              LEFT JOIN event_values e2 ON e1.property = e2.property AND toInt64(e1.rn) = toInt64(e2.rn) + 1 AND #{group_names.map { |name| "e1.#{name} = e2.#{name}" }.join(" AND ")}
            ),
            events_filtered AS (
              SELECT
                #{group_names.join(", ")},
                property,
                operation_type,
                timestamp,
                rn,
                -- Check if current event should be ignored
                if(
                  -- Check if next event on same day has opposite operation type
                  (rn != 1 AND toDate(next_timestamp) = toDate(timestamp) AND next_operation_type != operation_type)
                  OR
                  -- Check if previous event has same operation type
                  prev_operation_type = operation_type,
                  true,
                  false
                ) AS is_ignored
              FROM events_with_prev
            )

            SELECT
              #{group_names.join(", ")},
              coalesce(SUM(period_ratio), 0) as aggregation
            FROM (
              SELECT
                (#{grouped_period_ratio_sql}) AS period_ratio,
                #{group_names.join(", ")}
              FROM events_filtered
              WHERE is_ignored = false
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
            event_values AS (
              SELECT
                property,
                operation_type,
                timestamp,
                ROW_NUMBER() OVER (PARTITION BY property ORDER BY timestamp) AS rn
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{operation_value_sql} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, timestamp, operation_type
            ),
            events_with_next AS (
              SELECT
                e1.property,
                e1.operation_type,
                e1.timestamp,
                e1.rn,
                e2.operation_type AS next_operation_type,
                e2.timestamp AS next_timestamp
              FROM event_values e1
              LEFT JOIN event_values e2 ON e1.property = e2.property AND toInt64(e1.rn) = toInt64(e2.rn) - 1
            ),
            events_with_prev AS (
              SELECT
                e1.property,
                e1.operation_type,
                e1.timestamp,
                e1.rn,
                e1.next_operation_type,
                e1.next_timestamp,
                e2.operation_type AS prev_operation_type
              FROM events_with_next e1
              LEFT JOIN event_values e2 ON e1.property = e2.property AND toInt64(e1.rn) = toInt64(e2.rn) + 1
            ),
            events_filtered AS (
              SELECT
                property,
                operation_type,
                timestamp,
                rn,
                -- Check if current event should be ignored
                if(
                  -- Check if next event on same day has opposite operation type
                  (rn != 1 AND toDate(next_timestamp) = toDate(timestamp) AND next_operation_type != operation_type)
                  OR
                  -- Check if previous event has same operation type
                  prev_operation_type = operation_type,
                  true,
                  false
                ) AS is_ignored
              FROM events_with_prev
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
              FROM events_filtered
              WHERE is_ignored = false
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
