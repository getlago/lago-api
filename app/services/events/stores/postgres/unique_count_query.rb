# frozen_string_literal: true

module Events
  module Stores
    module Postgres
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

            SELECT COALESCE(SUM(sum_adjusted_value), 0) AS aggregation FROM event_values
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
                  #{operation_value_sql} AS adjusted_value
                FROM events_data
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY property, operation_type, timestamp
            )

            SELECT COALESCE(SUM(period_ratio), 0) as aggregation
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
              GROUP BY #{group_names}, property
            )

            SELECT
              #{group_names},
              COALESCE(SUM(sum_adjusted_value), 0) as aggregation
            FROM event_values
            GROUP BY #{group_names}
          SQL
        end

        def grouped_prorated_query
          <<-SQL
            #{grouped_events_cte_sql},

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
                FROM events_data
                ORDER BY timestamp ASC
              ) adjusted_event_values
              WHERE adjusted_value != 0 -- adjusted_value = 0 does not impact the total
              GROUP BY #{group_names}, property, operation_type, timestamp
            )

            SELECT
              #{group_names},
              COALESCE(SUM(period_ratio), 0) as aggregation
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
              #{operation_value_sql}
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
                timestamp
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

        delegate :events, :charges_duration, :sanitized_property_name, to: :store

        def events_cte_sql
          # NOTE: Common table expression returning event's timestamp, property name and operation type.
          <<-SQL
            WITH events_data AS (#{
              events
                .select(
                  "timestamp, \
                  #{sanitized_property_name} AS property, \
                  COALESCE(events.properties->>'operation_type', 'add') AS operation_type"
                ).to_sql
            })
          SQL
        end

        def grouped_events_cte_sql
          groups = store.grouped_by.map.with_index do |group, index|
            "#{sanitized_property_name(group)} AS g_#{index}"
          end

          <<-SQL
            WITH events_data AS (#{
              events
                .select(
                  "#{groups.join(", ")}, \
                  timestamp, \
                  #{sanitized_property_name} AS property, \
                  COALESCE(events.properties->>'operation_type', 'add') AS operation_type"
                ).to_sql
            })
          SQL
        end

        def operation_value_sql
          # NOTE: Returns 1 for relevant addition, -1 for relevant removal
          # If property already added, another addition returns 0 ; it returns 1 otherwise
          # If property already removed or not yet present, another removal returns 0 ; it returns -1 otherwise
          <<-SQL
            CASE WHEN operation_type = 'add'
            THEN
              CASE WHEN LAG(operation_type, 1) OVER (PARTITION BY property ORDER BY timestamp) = 'add'
              THEN 0
              ELSE 1
              END
            ELSE
              CASE LAG(operation_type, 1, 'remove') OVER (PARTITION BY property ORDER BY timestamp)
                WHEN 'remove' THEN 0
                ELSE -1
              END
            END
          SQL
        end

        def grouped_operation_value_sql
          # NOTE: Returns 1 for relevant addition, -1 for relevant removal
          # If property already added, another addition returns 0 ; it returns 1 otherwise
          # If property already removed or not yet present, another removal returns 0 ; it returns -1 otherwise
          <<-SQL
            CASE WHEN operation_type = 'add'
            THEN
              CASE WHEN LAG(operation_type, 1) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp) = 'add'
              THEN 0
              ELSE 1
              END
            ELSE
              CASE LAG(operation_type, 1, 'remove') OVER (PARTITION BY #{group_names}, property ORDER BY timestamp)
                WHEN 'remove' THEN 0
                ELSE -1
              END
            END
          SQL
        end

        def period_ratio_sql
          <<-SQL
            CASE WHEN operation_type = 'add'
            THEN
              -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
              (
                (
                  DATE((
                    -- NOTE: if following event is older than the start of the period, we use the start of the period as the reference
                    CASE WHEN (LEAD(timestamp, 1, :to_datetime) OVER (PARTITION BY property ORDER BY timestamp)) < :from_datetime
                    THEN :from_datetime
                    ELSE LEAD(timestamp, 1, :to_datetime) OVER (PARTITION BY property ORDER BY timestamp) + interval '1' day
                    END
                  )::timestamptz AT TIME ZONE :timezone)
                  - DATE((
                    -- NOTE: if events is older than the start of the period, we use the start of the period as the reference
                    CASE WHEN timestamp < :from_datetime THEN :from_datetime ELSE timestamp END
                  )::timestamptz AT TIME ZONE :timezone)
                )::numeric
              )
              /
              -- NOTE: full duration of the period
              #{charges_duration}::numeric
            ELSE
              0 -- NOTE: duration was null so usage is null
            END
          SQL
        end

        def grouped_period_ratio_sql
          <<-SQL
            CASE WHEN operation_type = 'add'
            THEN
              -- NOTE: duration in seconds between current event and next one - using end of period as final boundaries
              (
                (
                  DATE((
                    -- NOTE: if following event is older than the start of the period, we use the start of the period as the reference
                    CASE WHEN (LEAD(timestamp, 1, :to_datetime) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp)) < :from_datetime
                    THEN :from_datetime
                    ELSE LEAD(timestamp, 1, :to_datetime) OVER (PARTITION BY #{group_names}, property ORDER BY timestamp)
                    END
                  )::timestamptz AT TIME ZONE :timezone)
                  - DATE((
                    -- NOTE: if events is older than the start of the period, we use the start of the period as the reference
                    CASE WHEN timestamp < :from_datetime THEN :from_datetime ELSE timestamp END
                  )::timestamptz AT TIME ZONE :timezone)
                )::numeric
                + 1
              )
              /
              -- NOTE: full duration of the period
              #{charges_duration}::numeric
            ELSE
              0 -- NOTE: duration was null so usage is null
            END
          SQL
        end

        def group_names
          @group_names ||= store.grouped_by.map.with_index { |_, index| "g_#{index}" }.join(', ')
        end
      end
    end
  end
end
