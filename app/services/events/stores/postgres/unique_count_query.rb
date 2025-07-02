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
              GROUP BY property, operation_type, timestamp
            ),
            merged_events AS (
              SELECT
                e.property,
                e.timestamp,
                e.operation_type,
                e.rn,
                false AS is_ignored,  -- not ignored
                e.operation_type AS previous_not_ignored_operation_type
              FROM event_values e
              WHERE e.rn = 1

              UNION ALL
              SELECT
                e.property,
                e.timestamp,
                e.operation_type,
                e.rn,
                CASE
                  -- Check if next event on same day has opposite operation type so it nullifies this one at the same day
                  WHEN #{existing_event_opposite_operation_type_sql}
                  THEN true
                  -- Check if previous not ignored event has same operation type
                  WHEN r.previous_not_ignored_operation_type = e.operation_type THEN true
                  ELSE false
                END AS is_ignored,

                -- Update previous_not_ignored_operation_type only if not ignored
                CASE
                  -- Check if next event on same day has opposite operation type so it nullifies this one at the same day, so we can ignore it
                  WHEN #{existing_event_opposite_operation_type_sql}
                  THEN r.previous_not_ignored_operation_type
                  -- Check if previous not ignored event has same operation type
                  WHEN e.operation_type = r.previous_not_ignored_operation_type THEN r.previous_not_ignored_operation_type
                  ELSE e.operation_type
                END AS previous_not_ignored_operation_type
              FROM merged_events r
              JOIN event_values e
                ON e.property = r.property AND e.rn = r.rn + 1
            )

            SELECT COALESCE(SUM(period_ratio), 0) as aggregation
            FROM (
              SELECT (#{period_ratio_sql}) AS period_ratio
              FROM merged_events
              WHERE is_ignored = false
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
            WITH RECURSIVE events_data AS (#{
              events(ordered: true)
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
              events(ordered: true)
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
              #{charges_duration || 1}::numeric
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
              #{charges_duration || 1}::numeric
            ELSE
              0 -- NOTE: duration was null so usage is null
            END
          SQL
        end

        # IS_IGNORED logic for prorated aggregation desired behaviour is:
        # 27th property add
        # 27th property remove
        # 27th property add

        # 28th property add (operation is 0, so it's already filtered by previous query)
        # 28th property remove
        # --- end of unit 0, prorated 2 days
        # 30th property add
        # --the result of 30 is 1 -> prorated 1 day
        # for this we want to have only 2 events: 27th-28th and 30th to 30th

        # summary table:
        # 27th property add not_ignore
        # 27th property remove ignore
        # 27th property add ignore
        # 28th property remove not_ignore
        # 30th property add not_ignore
        # So the rule is:
        # -- for the same day, we look at next event. if it's opposite of current, current can be ignored
        # -- we look at previous not ignored event. if the operation type matches. we can ignore current
        def existing_event_opposite_operation_type_sql
          <<-SQL
            (
              SELECT
                1
              FROM event_values next_event
              WHERE next_event.property = e.property
                AND next_event.rn = e.rn + 1
                AND DATE(next_event.timestamp) = DATE(e.timestamp)
                AND next_event.operation_type <> e.operation_type
              LIMIT 1
            ) = 1
          SQL
        end

        def group_names
          @group_names ||= store.grouped_by.map.with_index { |_, index| "g_#{index}" }.join(", ")
        end
      end
    end
  end
end
