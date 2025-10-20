# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseStore < BaseStore
      DECIMAL_SCALE = 26
      DECIMAL_DATE_SCALE = 10

      def events(force_from: false, ordered: false)
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          scope = ::Clickhouse::EventsEnriched.where(external_subscription_id: subscription.external_id)
            .where(organization_id: subscription.organization.id)
            .where(code:)

          scope = scope.order(timestamp: :asc) if ordered

          scope = scope.where("events_enriched.timestamp >= ?", from_datetime) if force_from || use_from_boundary
          scope = scope.where("events_enriched.timestamp <= ?", applicable_to_datetime) if applicable_to_datetime
          scope = scope.limit_by(1, "events_enriched.transaction_id")

          scope = apply_grouped_by_values(scope) if grouped_by_values?
          filters_scope(scope)
        end
      end

      def events_sql(force_from: false, ordered: false, select: arel_table[Arel.star])
        query = arel_table.where(
          arel_table[:external_subscription_id].eq(subscription.external_id)
          .and(arel_table[:organization_id].eq(subscription.organization.id)
          .and(arel_table[:code].eq(code)))
        )

        query = query.order(arel_table[:timestamp].desc, arel_table[:value].asc) if ordered

        query = query.where(arel_table[:timestamp].gteq(from_datetime)) if force_from || use_from_boundary
        query = query.where(arel_table[:timestamp].lteq(applicable_to_datetime)) if applicable_to_datetime
        query = query.limit_by(1, "events_enriched.transaction_id")

        query = apply_arel_grouped_by_values(query) if grouped_by_values?
        query = arel_filters_scope(query)

        query.project(select).to_sql
      end

      def distinct_codes
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          ::Clickhouse::EventsEnriched
            .where(external_subscription_id: subscription.external_id)
            .where(organization_id: subscription.organization.id)
            .where("events_enriched.timestamp >= ?", from_datetime)
            .where("events_enriched.timestamp <= ?", applicable_to_datetime)
            .pluck("DISTINCT(code)")
        end
      end

      def events_values(limit: nil, force_from: false, exclude_event: false)
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          scope = events(force_from:, ordered: true)

          scope = scope.where("events_enriched.transaction_id != ?", filters[:event].transaction_id) if exclude_event
          scope = scope.limit(limit) if limit

          scope.pluck("events_enriched.decimal_value")
        end
      end

      def last_event
        Events::Stores::Utils::ClickhouseConnection.with_retry { events(ordered: true).last }
      end

      def grouped_last_event
        groups, group_names = grouped_arel_columns

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            ordered: true,
            select: groups + [arel_table[:decimal_value].as("property"), arel_table[:timestamp]]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              DISTINCT ON (#{group_names}) #{group_names},
              events.timestamp,
              property
            FROM events
            ORDER BY #{group_names}, events.timestamp DESC
          SQL

          prepare_grouped_result(connection.select_all(sql).rows, timestamp: true)
        end
      end

      def prorated_events_values(total_duration)
        ratio_sql = Events::Stores::Utils::ClickhouseSqlHelpers.duration_ratio_sql(
          "events_enriched.timestamp", to_datetime, total_duration, timezone
        )

        Events::Stores::Utils::ClickhouseConnection.with_retry do
          events(ordered: true).pluck(Arel.sql("events_enriched.decimal_value * (#{ratio_sql})"))
        end
      end

      def count
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = <<-SQL
          WITH events AS (#{events_sql})

          SELECT count()
          FROM events
          SQL

          connection.select_value(sql).to_i
        end
      end

      def grouped_count
        groups, group_names = grouped_arel_columns

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            ordered: true,
            select: groups + [arel_table[:transaction_id]]
          )

          sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            #{group_names},
            toDecimal32(count(), 0)
          FROM events
          GROUP BY #{group_names}
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      # NOTE: check if an event created before the current on belongs to an active (as in present and not removed)
      #       unique property
      def active_unique_property?(event)
        previous_event = Events::Stores::Utils::ClickhouseConnection.with_retry do
          events
            .where("events_enriched.properties[?] = ?", aggregation_property, event.properties[aggregation_property])
            .where("events_enriched.timestamp < ?", event.timestamp)
            .order(timestamp: :desc)
            .first
        end

        previous_event && (
          previous_event.properties["operation_type"].nil? ||
          previous_event.properties["operation_type"] == "add"
        )
      end

      def unique_count
        result = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.query),
              {decimal_date_scale: DECIMAL_DATE_SCALE}
            ]
          )
          connection.select_one(sql)
        end

        result["aggregation"]
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def unique_count_breakdown
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)

          connection.select_all(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              [
                sanitize_colon(query.breakdown_query),
                {decimal_date_scale: DECIMAL_DATE_SCALE}
              ]
            )
          ).rows
        end
      end

      def prorated_unique_count
        result = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.prorated_query),
              {
                from_datetime:,
                to_datetime:,
                decimal_date_scale: DECIMAL_DATE_SCALE,
                timezone: customer.applicable_timezone
              }
            ]
          )
          connection.select_one(sql)
        end

        result["aggregation"]
      end

      def prorated_unique_count_breakdown(with_remove: false)
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.prorated_breakdown_query(with_remove:)),
              {
                from_datetime:,
                to_datetime:,
                decimal_date_scale: DECIMAL_DATE_SCALE,
                timezone: customer.applicable_timezone
              }
            ]
          )

          connection.select_all(sql).to_a
        end
      end

      def grouped_unique_count
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.grouped_query),
              {
                to_datetime:,
                decimal_date_scale: DECIMAL_DATE_SCALE
              }
            ]
          )

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def grouped_prorated_unique_count
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.grouped_prorated_query),
              {
                from_datetime:,
                to_datetime:,
                decimal_date_scale: DECIMAL_DATE_SCALE,
                timezone: customer.applicable_timezone
              }
            ]
          )
          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def max
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = <<-SQL
          WITH events AS (#{events_sql})

          SELECT max(events.decimal_value)
          FROM events
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_max
        groups, group_names = grouped_arel_columns

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            ordered: true,
            select: groups + [arel_table[:decimal_value].as("property"), arel_table[:timestamp]]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              #{group_names},
              MAX(property)
            FROM events
            GROUP BY #{group_names}
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def last
        value = Events::Stores::Utils::ClickhouseConnection.with_retry do
          events(ordered: true).last&.properties&.[](aggregation_property)
        end

        return value unless value

        BigDecimal(value)
      end

      def grouped_last
        groups, group_names = grouped_arel_columns

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            ordered: true,
            select: groups + [arel_table[:decimal_value].as("property"), arel_table[:timestamp]]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              DISTINCT ON (#{group_names}) #{group_names},
              property
            FROM events
            ORDER BY #{group_names}, events.timestamp DESC
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def sum_precise_total_amount_cents
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = <<-SQL
            WITH events AS (#{events_sql})

            SELECT SUM(events.precise_total_amount_cents)
            FROM events
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_sum_precise_total_amount_cents
        groups, group_names = grouped_arel_columns

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(select: groups + [arel_table[:precise_total_amount_cents].as("property")])

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              #{group_names},
              sum(events.property)
            FROM events
            GROUP BY #{group_names}
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def sum
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = <<-SQL
            WITH events AS (#{events_sql})

            SELECT sum(events.decimal_value)
            FROM events
          SQL

          connection.select_value(sql) || 0
        end
      end

      def grouped_sum
        groups, group_names = grouped_arel_columns

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(select: groups + [arel_table[:decimal_value].as("property")])

          sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            #{group_names},
            sum(events.property)
          FROM events
          GROUP BY #{group_names}
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          Events::Stores::Utils::ClickhouseSqlHelpers.duration_ratio_sql(
            "events_enriched.timestamp", to_datetime, period_duration, timezone
          )
        end

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            select: [
              Arel::Nodes::InfixOperation.new(
                "*",
                arel_table[:decimal_value],
                Arel::Nodes::Grouping.new(Arel::Nodes::SqlLiteral.new(ratio.to_s))
              ).as("prorated_value")
            ]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT sum(events.prorated_value)
            FROM events
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        groups, group_names = grouped_arel_columns

        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          Events::Stores::Utils::ClickhouseSqlHelpers.duration_ratio_sql("events_enriched.timestamp", to_datetime, period_duration, timezone)
        end

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            select: groups + [
              Arel::Nodes::InfixOperation.new(
                "*",
                arel_table[:decimal_value],
                Arel::Nodes::Grouping.new(Arel::Nodes::SqlLiteral.new(ratio.to_s))
              ).as("prorated_value")
            ]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              #{group_names},
              sum(events.prorated_value)
            FROM events
            GROUP BY #{group_names}
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def sum_date_breakdown
        date_field = Events::Stores::Utils::ClickhouseSqlHelpers.date_in_customer_timezone_sql("events_enriched.timestamp", timezone)

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            select: [
              Arel::Nodes::NamedFunction.new(
                "toDate",
                [Arel::Nodes::SqlLiteral.new(date_field)]
              ).as("day"),
              arel_table[:decimal_value].as("property")
            ]
          )

          sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            events.day,
            sum(events.property) AS day_sum
          FROM events
          GROUP BY events.day
          ORDER BY events.day asc
          SQL

          connection.select_all(Arel.sql(sql)).rows.map do |row|
            {date: row.first.to_date, value: row.last}
          end
        end
      end

      def weighted_sum(initial_value: 0)
        result = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::WeightedSumQuery.new(store: self)

          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.query),
              {
                from_datetime:,
                to_datetime: to_datetime.ceil,
                decimal_scale: DECIMAL_SCALE,
                initial_value: initial_value || 0
              }
            ]
          )

          connection.select_one(sql)
        end
        result["aggregation"]
      end

      def grouped_weighted_sum(initial_values: [])
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Clickhouse::WeightedSumQuery.new(store: self)

          # NOTE: build the list of initial values for each groups
          #       from the events in the period
          formated_initial_values = grouped_count.map do |group|
            value = 0
            previous_group = initial_values.find { |g| g[:groups] == group[:groups] }
            value = previous_group[:value] if previous_group
            {groups: group[:groups], value:}
          end

          # NOTE: add the initial values for groups that are not in the events
          initial_values.each do |intial_value|
            next if formated_initial_values.find { |g| g[:groups] == intial_value[:groups] }

            formated_initial_values << intial_value
          end
          return [] if formated_initial_values.empty?

          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.grouped_query(initial_values: formated_initial_values)),
              {
                from_datetime:,
                to_datetime: to_datetime.ceil,
                decimal_scale: DECIMAL_SCALE
              }
            ]
          )

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def weighted_sum_breakdown(initial_value: 0)
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::Clickhouse::WeightedSumQuery.new(store: self)

          rows = connection.select_all(
            ActiveRecord::Base.sanitize_sql_for_conditions(
              [
                sanitize_colon(query.breakdown_query),
                {
                  from_datetime:,
                  to_datetime: to_datetime.ceil,
                  decimal_scale: DECIMAL_SCALE,
                  initial_value: initial_value || 0
                }
              ]
            )
          ).rows
          # `date_diff` actually returns an `Int64` and ActiveRecord transform that into a `String`. If we cast the
          # result in a `Int32`, then we get the result as `Integer`:
          # ```ruby
          # lago-api(staging)> Clickhouse::BaseRecord.connection.select_one("SELECT 1::Int64")
          # => {"CAST('1', 'Int64')" => "1"}
          # lago-api(staging)> Clickhouse::BaseRecord.connection.select_one("SELECT 1::Int32")
          # => {"CAST('1', 'Int32')" => 1}
          # ```
          # To keep consistency with the PG implementation, we call `#to_i` on the value.
          rows.map do |(timestamp, difference, cumul, second_duration, period_ratio)|
            [timestamp, difference, cumul, second_duration.to_i, period_ratio]
          end
        end
      end

      def filters_scope(scope)
        matching_filters.each do |key, values|
          scope = scope.where("events_enriched.properties[?] IN ?", key.to_s, values)
        end

        conditions = ignored_filters.map do |filters|
          filters.map do |key, values|
            ActiveRecord::Base.sanitize_sql_for_conditions(
              ["(coalesce(events_enriched.properties[?], '') IN (?))", key.to_s, values.map(&:to_s)]
            )
          end.join(" AND ")
        end
        sql = conditions.map { "(#{it})" }.join(" OR ")
        scope = scope.where.not(sql) if sql.present?

        scope
      end

      def arel_filters_scope(scope)
        matching_filters.each do |key, values|
          scope = scope.where(
            Arel::Nodes::SqlLiteral.new(sanitized_property_name(key.to_s)).in(values.map(&:to_s))
          )
        end

        conditions = ignored_filters.map do |filters|
          filters.map do |key, values|
            ActiveRecord::Base.sanitize_sql_for_conditions(
              ["(coalesce(events_enriched.properties[?], '') IN (?))", key.to_s, values.map(&:to_s)]
            )
          end.join(" AND ")
        end
        sql = conditions.map { "(#{it})" }.join(" OR ")
        scope = scope.where(Arel::Nodes::Not.new(Arel::Nodes::SqlLiteral.new(sql))) if conditions.present?

        scope
      end

      def apply_grouped_by_values(scope)
        grouped_by_values.each do |grouped_by, grouped_by_value|
          scope = if grouped_by_value.present?
            scope.where("events_enriched.properties[?] = ?", grouped_by, grouped_by_value)
          else
            scope.where("COALESCE(events_enriched.properties[?], '') = ''", grouped_by)
          end
        end

        scope
      end

      def apply_arel_grouped_by_values(query)
        grouped_by_values.each do |grouped_by, grouped_by_value|
          query = if grouped_by_value.present?
            query.where(Arel::Nodes::SqlLiteral.new(sanitized_property_name(grouped_by)).eq(grouped_by_value))
          else
            query.where(
              Arel::Nodes::NamedFunction.new(
                "COALESCE",
                [
                  Arel::Nodes::SqlLiteral.new(sanitized_property_name(grouped_by)),
                  Arel::Nodes::SqlLiteral.new("''")
                ]
              ).eq(Arel::Nodes::SqlLiteral.new("''"))
            )
          end
        end

        query
      end

      def sanitized_property_name(property = aggregation_property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ["events_enriched.properties[?]", property]
        )
      end

      # NOTE: returns the values for each groups
      #       The result format will be an array of hash with the format:
      #       [{ groups: { 'cloud' => 'aws', 'region' => 'us_east_1' }, value: 12.9 }, ...]
      def prepare_grouped_result(rows, timestamp: false)
        rows.map do |row|
          last_group = timestamp ? -2 : -1
          groups = row.flatten[...last_group].map(&:presence)

          result = {
            groups: grouped_by.each_with_object({}).with_index { |(g, r), i| r.merge!(g => groups[i]) },
            value: row.last
          }

          result[:timestamp] = row[-2] if timestamp

          result
        end
      end

      def arel_table
        @arel_table ||= ::Clickhouse::EventsEnriched.arel_table
      end

      def grouped_arel_columns
        [
          grouped_by.map.with_index do |group, index|
            Arel::Nodes::SqlLiteral.new(sanitized_property_name(group)).as("g_#{index}")
          end,
          grouped_by.map.with_index { |_, index| "g_#{index}" }.join(", ")
        ]
      end
    end
  end
end
