# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseEnrichedStore < BaseStore
      include Events::Stores::Utils::QueryHelpers
      include Events::Stores::Utils::ClickhouseSqlHelpers

      def events
        raise NotImplementedError
      end

      def events_cte_queries(**args)
        return events_cte_queries_with_deduplication(**args) if deduplicate

        events_cte_queries_without_deduplication(**args)
      end

      def events_cte_queries_without_deduplication(force_from: false, ordered: false, select: arel_table[Arel.star], deduplicated_columns: [], to_datetime: nil)
        query = arel_table.where(
          arel_table[:subscription_id].eq(subscription.id)
            .and(arel_table[:organization_id].eq(subscription.organization_id))
            .and(arel_table[:charge_id].eq(charge_id))
        ).then { with_charge_filter_id(it) }

        query = query.order(arel_table[:timestamp].desc, arel_table[:value].asc) if ordered

        query = with_timestamp_boundaries(
          query,
          (from_datetime if force_from || use_from_boundary),
          to_datetime || applicable_to_datetime
        )

        query = apply_arel_grouped_by_values(query) if grouped_by_values?

        {"events" => query.project(select).to_sql}
      end

      def events_cte_queries_with_deduplication(force_from: false, ordered: false, select: arel_table[Arel.star], deduplicated_columns: [], to_datetime: nil)
        # Ensure presence of one of value or decimal_value for the ordering
        order_column = deduplicated_columns.include?("decimal_value") ? "decimal_value" : "value"
        deduplicated_columns << order_column if ordered

        base_sql = deduplicated_events_sql(
          from_datetime: (from_datetime if force_from || use_from_boundary),
          to_datetime: to_datetime.presence || applicable_to_datetime.presence,
          deduplicated_columns:
        ).to_sql

        query = Arel::Table.new(:events_enriched_expanded)
        query = query.order(arel_table[:timestamp].desc, arel_table[order_column.to_sym]) if ordered
        query = apply_arel_grouped_by_values(query) if grouped_by_values?

        {
          "events_enriched_expanded" => base_sql, # Override events table name with deduplicated events
          "events" => query.project(select).to_sql
        }
      end

      # Clickhouse cannot garanty that events_enriched_expanded will be deduplicated all the time
      # To address this problem, we have to implement deduplication at query time.
      # This is done by grouping events on transaction_id and timestamp (unicity key) and
      # by using `argMax` function, to keep only the most recent event of each group
      def deduplicated_events_sql(from_datetime:, to_datetime:, deduplicated_columns: [])
        query = arel_table.where(
          arel_table[:subscription_id].eq(subscription.id)
            .and(arel_table[:organization_id].eq(subscription.organization_id))
            .and(arel_table[:charge_id].eq(charge_id))
        ).then { with_charge_filter_id(it) }
          .then { with_timestamp_boundaries(it, from_datetime, to_datetime) }

        columns = deduplicated_columns.dup

        if grouped_by.present? || grouped_by_values.present?
          columns << "sorted_grouped_by"
        end

        arel_columns = columns.uniq.map do
          Arel::Nodes::NamedFunction.new("argMax", [arel_table[it.to_sym], arel_table[:enriched_at]]).as(it)
        end

        query = query.group(
          arel_table[:charge_id],
          arel_table[:charge_filter_id],
          arel_table[:subscription_id],
          arel_table[:organization_id],
          arel_table[:timestamp],
          arel_table[:transaction_id]
        )
        query.project(
          [
            arel_table[:charge_id],
            arel_table[:charge_filter_id],
            arel_table[:subscription_id],
            arel_table[:organization_id],
            arel_table[:timestamp],
            arel_table[:transaction_id]
          ] + arel_columns
        )
      end

      def events_values
        raise NotImplementedError
      end

      def last_event
        raise NotImplementedError
      end

      def prorated_events_values
        raise NotImplementedError
      end

      def count
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[value]), <<-SQL)
            SELECT count()
            FROM events
          SQL

          connection.select_value(sql).to_i
        end
      end

      def grouped_count
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[value], select: [arel_table[:sorted_grouped_by]]), <<-SQL)
            SELECT
              sorted_grouped_by as groups,
              toDecimal32(count(), 0) as value
            FROM events
            GROUP BY sorted_grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql))
        end
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

      def active_unique_property?(event)
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(
            deduplicated_columns: %w[value properties],
            to_datetime: event.timestamp - 0.001.seconds,
            ordered: true
          ), <<-SQL)
            SELECT properties
            FROM events
            WHERE value = ?
            LIMIT 1
          SQL

          previous_properties = connection.select_one(
            ActiveRecord::Base.sanitize_sql_for_conditions([sql, event.properties[aggregation_property].to_s])
          )
          return false if previous_properties.nil?

          operation_type = previous_properties.dig("properties", "operation_type")
          operation_type.nil? || operation_type == "add"
        end
      end

      def max
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[decimal_value]), <<-SQL)
            SELECT max(events.decimal_value)
            FROM events
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_max
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(
            deduplicated_columns: %w[decimal_value],
            select: [arel_table[:sorted_grouped_by], arel_table[:decimal_value]]
          ), <<-SQL)
            SELECT
              sorted_grouped_by as groups,
              MAX(events.decimal_value) as value
            FROM events
            GROUP BY sorted_grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql))
        end
      end

      def last
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[decimal_value]), <<-SQL)
            SELECT decimal_value
            FROM events
            ORDER BY timestamp DESC
            LIMIT 1
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_last
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[decimal_value]), <<-SQL)
            SELECT
              DISTINCT ON (sorted_grouped_by) sorted_grouped_by as groups,
              events.decimal_value as value
            FROM events
            ORDER BY sorted_grouped_by, timestamp DESC
          SQL

          prepare_grouped_result(connection.select_all(sql))
        end
      end

      def sum
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[decimal_value]), <<-SQL)
            SELECT sum(events.decimal_value)
            FROM events
          SQL

          connection.select_value(sql) || 0
        end
      end

      def grouped_sum
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[decimal_value]), <<-SQL)
            SELECT
              sorted_grouped_by as groups,
              sum(events.decimal_value) as value
            FROM events
            GROUP BY sorted_grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql))
        end
      end

      def sum_precise_total_amount_cents
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[precise_total_amount_cents]), <<-SQL)
            SELECT COALESCE(sum(events.precise_total_amount_cents), 0)
            FROM events
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_sum_precise_total_amount_cents
        Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[precise_total_amount_cents]), <<-SQL)
            SELECT
              sorted_grouped_by as groups,
              sum(events.precise_total_amount_cents) as value
            FROM events
            GROUP BY sorted_grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql))
        end
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql(
            "events_enriched_expanded.timestamp", to_datetime, period_duration, timezone
          )
        end

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          ctes_sql = events_cte_queries(
            select: [
              Arel::Nodes::InfixOperation.new(
                "*",
                arel_table[:decimal_value],
                Arel::Nodes::Grouping.new(Arel::Nodes::SqlLiteral.new(ratio.to_s))
              ).as("prorated_value")
            ],
            deduplicated_columns: %w[decimal_value]
          )

          sql = with_ctes(ctes_sql, <<-SQL)
            SELECT sum(events.prorated_value)
            FROM events
          SQL

          connection.select_value(sql)
        end
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql(
            "events_enriched_expanded.timestamp", to_datetime, period_duration, timezone
          )
        end

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          ctes_sql = events_cte_queries(
            select: [arel_table[:sorted_grouped_by]] + [
              Arel::Nodes::InfixOperation.new(
                "*",
                arel_table[:decimal_value],
                Arel::Nodes::Grouping.new(Arel::Nodes::SqlLiteral.new(ratio.to_s))
              ).as("prorated_value")
            ],
            deduplicated_columns: %w[decimal_value]
          )

          sql = with_ctes(ctes_sql, <<-SQL)
            SELECT
              sorted_grouped_by as groups,
              sum(events.prorated_value) as value
            FROM events
            GROUP BY sorted_grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql))
        end
      end

      def sum_date_breakdown
        date_field = date_in_customer_timezone_sql("events_enriched_expanded.timestamp", timezone)

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          ctes_sql = events_cte_queries(
            select: [
              Arel::Nodes::NamedFunction.new(
                "toDate",
                [Arel::Nodes::SqlLiteral.new(date_field)]
              ).as("day"),
              arel_table[:decimal_value].as("property")
            ],
            deduplicated_columns: %w[decimal_value]
          )

          sql = with_ctes(ctes_sql, <<-SQL)
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

        BigDecimal(result["aggregation"].presence || 0)
      end

      def grouped_weighted_sum(initial_values: [])
        raise NotImplementedError
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

      def arel_table
        @arel_table ||= ::Clickhouse::EventsEnrichedExpanded.arel_table
      end

      def group_names
        "grouped_by"
      end

      def operation_type_sql
        "events_enriched_expanded.sorted_properties['operation_type']"
      end

      def with_timestamp_boundaries(query, from_datetime, to_datetime)
        query = query.where(arel_table[:timestamp].gteq(from_datetime)) if from_datetime
        query = query.where(arel_table[:timestamp].lteq(to_datetime)) if to_datetime
        query
      end

      def with_charge_filter_id(query)
        if charge_filter_id.present?
          query.where(arel_table[:charge_filter_id].eq(charge_filter_id))
        else
          query.where(arel_table[:charge_filter_id].eq(""))
        end
      end

      def apply_arel_grouped_by_values(query)
        # NOTE: grouped_by is populated from a sorted Map(String, String) converted into a String
        #       to make it comparable, we need to sort the group keys and replace nil values with empty strings
        groups = grouped_by_values
          .sort_by { |key, _| key }
          .flat_map { |k, v| [Arel::Nodes.build_quoted(k), Arel::Nodes.build_quoted(v.presence || "")] }

        map_fn = Arel::Nodes::NamedFunction.new("map", groups)
        query.where(arel_table[:sorted_grouped_by].eq(map_fn))
      end

      def prepare_grouped_result(result, decimal: false)
        result.to_ary.map do |row|
          row.symbolize_keys.tap do |r|
            r[:groups] = r[:groups].transform_values(&:presence)
            r[:value] = decimal ? BigDecimal(r[:value].presence || 0) : r[:value]
          end
        end
      end
    end
  end
end
