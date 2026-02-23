# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseEnrichedStore < BaseStore
      include Events::Stores::Utils::QueryHelpers

      def events
        raise NotImplementedError
      end

      def events_cte_queries(**args)
        return events_cte_queries_with_deduplication(**args) if deduplicate

        events_cte_queries_without_deduplication(**args)
      end

      def events_cte_queries_without_deduplication(force_from: false, ordered: false, select: arel_table[Arel.star], deduplicated_columns: [])
        query = arel_table.where(
          arel_table[:subscription_id].eq(subscription.id)
            .and(arel_table[:organization_id].eq(subscription.organization_id))
            .and(arel_table[:charge_id].eq(charge_id))
        ).then { with_charge_filter_id(it) }

        query = query.order(arel_table[:timestamp].desc, arel_table[:value].asc) if ordered

        query = with_timestamp_boundaries(
          query,
          (from_datetime if force_from || use_from_boundary),
          applicable_to_datetime
        )

        query = apply_arel_grouped_by_values(query) if grouped_by_values?

        {"events" => query.project(select).to_sql}
      end

      def events_cte_queries_with_deduplication(force_from: false, ordered: false, select: arel_table[Arel.star], deduplicated_columns: [])
        # Ensure presence of one of value or decimal_value for the ordering
        order_column = deduplicated_columns.include?("decimal_value") ? "decimal_value" : "value"
        deduplicated_columns << order_column if ordered

        base_sql = deduplicated_events_sql(
          from_datetime: (from_datetime if force_from || use_from_boundary),
          to_datetime: (applicable_to_datetime if applicable_to_datetime),
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
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[value]), <<-SQL)
            SELECT
              sorted_grouped_by as groups,
              toDecimal32(count(), 0) as value
            FROM events
            GROUP BY sorted_grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql))
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
          sql = with_ctes(events_cte_queries(deduplicated_columns: %w[decimal_value]), <<-SQL)
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
        raise NotImplementedError
      end

      def grouped_sum
        raise NotImplementedError
      end

      def sum_precise_total_amount_cents
        raise NotImplementedError
      end

      def grouped_sum_precise_total_amount_cents
        raise NotImplementedError
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        raise NotImplementedError
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        raise NotImplementedError
      end

      def sum_date_breakdown
        raise NotImplementedError
      end

      def weighted_sum(initial_value: 0)
        raise NotImplementedError
      end

      def grouped_weighted_sum(initial_values: [])
        raise NotImplementedError
      end

      def arel_table
        @arel_table ||= ::Clickhouse::EventsEnrichedExpanded.arel_table
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
        #       to make it comparable, we need to sort the group keys and replace nil values with "<nil>" string
        groups = grouped_by_values
          .sort_by { |key, _| key }
          .flat_map { |k, v| [Arel::Nodes.build_quoted(k), Arel::Nodes.build_quoted(v.presence || "")] }

        map_fn = Arel::Nodes::NamedFunction.new("map", groups)
        query.where(arel_table[:sorted_grouped_by].eq(map_fn))
      end

      def prepare_grouped_result(result)
        result.to_ary.map do |row|
          row.symbolize_keys.tap { |r| r[:groups] = r[:groups].transform_values(&:presence) }
        end
      end
    end
  end
end
