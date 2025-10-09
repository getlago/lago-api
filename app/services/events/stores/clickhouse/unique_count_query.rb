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
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              GROUP BY property
            )

            SELECT coalesce(SUM(sum_adjusted_value), 0) AS aggregation FROM event_values
          SQL
        end

        # NOTE: current implementation of clickhouse's query is different from postgres's one:
        # IN POSTGRES we do not ignore Add events at all (they will be handled by adjusted value)
        # remove events are ignored if there is an Add event later on the save day. This query is done using
        # next_event.operation_type != event.operation_type, which is not supported in current verison of
        # Clickhouse we have on production, while this approach is more effective as it only queries one row and does not use
        # window function.
        # IN CLICKHOUSE we do not ignore Add events at all (they will be handled by adjusted value)
        # remove events are not ignored only if they are the last event of the day
        # this way we're not using not supported by clickhouse join on !=, but we use window function, which is less
        # performant than the postgres approach.
        # TODO: we should use the postgres approach in clickhouse as well, but it requires update CLickhouse
        def prorated_query
          <<-SQL
            #{events_cte_sql},
            same_day_ignored AS (
              SELECT
                property,
                operation_type,
                timestamp,
                #{ignore_remove_events_sql} AS is_ignored
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  -- Check if this is the last event of the day for this property
                  timestamp = MAX(timestamp) OVER (PARTITION BY property, toDate(timestamp, :timezone)) AS is_last_event_of_day
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) as e
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
                ORDER BY timestamp ASC, property ASC
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
                #{group_names},
                property,
                SUM(adjusted_value) AS sum_adjusted_value
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{group_names},
                  #{grouped_operation_value_sql} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              GROUP BY #{group_names}, property
            )

            SELECT
              #{group_names},
              coalesce(SUM(sum_adjusted_value), 0) as aggregation
            FROM event_values
            GROUP BY #{group_names}
          SQL
        end

        def grouped_prorated_query
          <<-SQL
            #{grouped_events_cte_sql},
            -- Only ignore remove events if they are NOT the last event of the day
            same_day_ignored AS (
              SELECT
                #{group_names},
                property,
                operation_type,
                timestamp,
                #{ignore_remove_events_sql} AS is_ignored
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{group_names},
                  -- Check if this is the last event of the day for this property and group
                  timestamp = MAX(timestamp) OVER (PARTITION BY #{group_names}, property, toDate(timestamp, :timezone)) AS is_last_event_of_day
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) as e
            ),
            -- Check if the operation type is the same as previous, so it nullifies this one
            event_values AS (
              SELECT
                #{group_names},
                property,
                operation_type,
                timestamp
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  #{group_names},
                  #{grouped_operation_value_sql} AS adjusted_value
                FROM same_day_ignored
                WHERE is_ignored = false
                ORDER BY timestamp ASC, property ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY #{group_names}, property, operation_type, timestamp
            )

            SELECT
              #{group_names},
              coalesce(SUM(period_ratio), 0) as aggregation
            FROM (
              SELECT
                (#{grouped_period_ratio_sql}) AS period_ratio,
                #{group_names}
              FROM event_values
            ) cumulated_ratios
            GROUP BY #{group_names}
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
              lagInFrame(operation_type, 1) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)
            FROM events_data
            ORDER BY timestamp ASC, property ASC
          SQL
        end

        def prorated_breakdown_query(with_remove: false)
          <<-SQL
            #{events_cte_sql},
            -- Only ignore remove events if they are NOT the last event of the day
            same_day_ignored AS (
              SELECT
                property,
                operation_type,
                timestamp,
                #{ignore_remove_events_sql} AS is_ignored
              FROM (
                SELECT
                  timestamp,
                  property,
                  operation_type,
                  -- Check if this is the last event of the day for this property
                  timestamp = MAX(timestamp) OVER (PARTITION BY property, toDate(timestamp, :timezone)) AS is_last_event_of_day
                FROM events_data
                ORDER BY timestamp ASC, property ASC
              ) as e
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
                ORDER BY timestamp ASC, property ASC
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
            ORDER BY timestamp ASC, property ASC
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
                (lagInFrame(operation_type, 1) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'add',
                toDecimal32(0, 0),
                toDecimal32(1, 0)
              )),
              (if(
                (lagInFrame(operation_type, 1, 'remove') OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'remove',
                toDecimal32(0, 0),
                toDecimal32(-1, 0)
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
                (lagInFrame(operation_type, 1) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'add',
                toDecimal32(0, 0),
                toDecimal32(1, 0)
              ))
              ,
              (if(
                (lagInFrame(operation_type, 1, 'remove') OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'remove',
                toDecimal32(0, 0),
                toDecimal32(-1, 0)
              ))
            )
          SQL
        end

        def period_ratio_sql
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
                             OVER (PARTITION BY property ORDER BY timestamp ASC
                                   ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                          ) < toDateTime64(:from_datetime, 3, 'UTC'),
                          toDateTime64(:from_datetime, 3, 'UTC'),
                          addDays(
                            (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC'))
                               OVER (PARTITION BY property ORDER BY timestamp ASC
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

        def grouped_period_ratio_sql
          <<-SQL
            if(
              operation_type = 'add',
              (
                toDecimal64(
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
                          (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC'))
                             OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC
                                   ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                          ) < toDateTime64(:from_datetime, 3, 'UTC'),
                          toDateTime64(:from_datetime, 3, 'UTC'),
                          addDays(
                            (leadInFrame(timestamp, 1, toDateTime64(:to_datetime, 3, 'UTC'))
                               OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC
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

        def ignore_remove_events_sql
          # NOTE: Only NOT ignore remove events if they are the last event of the day
          <<-SQL
            CASE
              -- Never ignore add events
              WHEN operation_type = 'add' THEN false
              -- Only ignore remove events if they are NOT the last event of the day
              WHEN operation_type = 'remove' AND NOT is_last_event_of_day THEN true
              ELSE false
            END
          SQL
        end

        def group_names
          @group_names ||= store.grouped_by.map.with_index { |_, index| "g_#{index}" }.join(", ")
        end
      end
    end
  end
end
