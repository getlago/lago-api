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
            -- Only NOT ignore remove events if they are the last event of the day
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
                ORDER BY timestamp ASC
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
                ORDER BY timestamp ASC
              ) adjusted_event_values
              GROUP BY #{group_names.join(", ")}, property
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
                ORDER BY timestamp ASC
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
                ORDER BY timestamp ASC
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
              anyOrNull(operation_type) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)
            FROM events_data
            ORDER BY timestamp ASC
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
                ORDER BY timestamp ASC
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
                ifNull((anyOrNull(operation_type) OVER (PARTITION BY property ORDER BY timestamp ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)), 'remove') = 'remove',
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
                (anyOrNull(operation_type) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)) = 'add',
                toDecimal128(0, :decimal_scale),
                toDecimal128(1, :decimal_scale)
              ))
              ,
              (if(
                ifNull((anyOrNull(operation_type) OVER (PARTITION BY #{group_names  .join(", ")}, property ORDER BY timestamp ASC ROWS BETWEEN 1 PRECEDING AND 1 PRECEDING)), 'remove') = 'remove',
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
                date_diff(
                  'days',
                  -- this is crasy: to_datetime is the 1 day of the NEXT billing period, so 1st of Aug - 31 of Jul returns correctly 1 day;
                  -- the timestamp of remove is the LAST DAY, that still should be calculated, but 3 Jul - 1 Jul == 2 days, but we need 3,
                  -- that's why for to_datetime when it's a timestamp we add 1 day to it
                  if(toDate(timestamp, :timezone) < toDate(:from_datetime, :timezone), toDate(:from_datetime, :timezone), toDate(timestamp, :timezone)),
                  if(
                    toDate(leadInFrame(timestamp, 1, toDate(:to_datetime, :timezone)) OVER (PARTITION BY property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) < toDate(:from_datetime, :timezone),
                    toDate(:from_datetime, :timezone),
                    leadInFrame(addDays(toDate(timestamp, :timezone), 1), 1, toDate(:to_datetime, :timezone)) OVER (PARTITION BY property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                  ),
                  :timezone
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
                date_diff(
                  'days',
                  if(toDate(timestamp, :timezone) < toDate(:from_datetime, :timezone), toDate(:from_datetime, :timezone), toDate(timestamp, :timezone)),
                  if(
                      toDate(leadInFrame(addDays(toDate(timestamp, :timezone), 1), 1, toDate(:to_datetime, :timezone)) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) < toDate(:from_datetime, :timezone),
                      toDate(:to_datetime, :timezone),
                      leadInFrame(addDays(toDate(timestamp, :timezone), 1), 1, toDate(:to_datetime, :timezone)) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp ASC ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)
                    ),
                  :timezone
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

        def ignore_remove_events_sql
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
