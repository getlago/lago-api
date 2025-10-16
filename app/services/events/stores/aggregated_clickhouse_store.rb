# frozen_string_literal: true

module Events
  module Stores
    class AggregatedClickhouseStore < BaseStore
      NIL_GROUP_VALUE = "<nil>"
      DECIMAL_SCALE = 26
      DECIMAL_DATE_SCALE = 10

      def events(force_from: false, ordered: false)
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          scope = ::Clickhouse::EventsEnrichedExpanded
            .where(subscription_id: subscription.id)
            .where(organization_id: subscription.organization_id)
            .where(charge_id:)
            .where(charge_filter_id: charge_filter_id || "")

          scope = scope.order(timestamp: :asc) if ordered
          scope = scope.where(timestamp: from_datetime..) if force_from || use_from_boundary
          scope = scope.where(timestamp: ..to_datetime) if to_datetime

          scope = if grouped_by_values?
            scope.where("toJSONString(sorted_grouped_by) = ?", formated_grouped_by_values)
          else
            # TODO: take grouped by into account when no grouped_by_values
            scope.where(sorted_grouped_by: "{}")
          end

          scope
        end
      end

      def events_sql(force_from: false, ordered: false, select: arel_enriched_table[Arel.star])
        query = arel_enriched_table.where(
          arel_enriched_table[:subscription_id].eq(subscription.id)
            .and(arel_enriched_table[:organization_id].eq(subscription.organization_id)
            .and(arel_enriched_table[:charge_id].eq(charge_id)
            .and(arel_enriched_table[:charge_filter_id].eq(charge_filter_id || ""))))
        )

        query = query.order(arel_enriched_table[:timestamp].desc, arel_enriched_table[:value].asc) if ordered

        query = query.where(arel_enriched_table[:timestamp].gteq(from_datetime)) if force_from || use_from_boundary
        query = query.where(arel_enriched_table[:timestamp].lteq(to_datetime)) if to_datetime
        query = query.limit_by(1, "events_enriched_expanded.transaction_id")

        query = if grouped_by_values?
          query.where(
            Arel::Nodes::NamedFunction.new(
              "toJSONString",
              [arel_enriched_table[:sorted_grouped_by]]
            ).eq(formated_grouped_by_values)
          )
        elsif grouped_by.blank?
          query.where(arel_enriched_table[:sorted_grouped_by].eq("{}"))
        else
          query
        end

        "#{query.project(select).to_sql} LIMIT 1 by events_enriched_expanded.transaction_id"
      end

      def aggregated_events_sql(force_from: false, select: aggregated_arel_table[Arel.star], group: nil, order: nil)
        query = aggregated_arel_table.where(
          aggregated_arel_table[:subscription_id].eq(subscription.id)
            .and(aggregated_arel_table[:organization_id].eq(subscription.organization_id)
            .and(aggregated_arel_table[:charge_id].eq(charge_id)
            .and(aggregated_arel_table[:charge_filter_id].eq(charge_filter_id || ""))))
        )

        query = query.where(aggregated_arel_table[:started_at].gteq(from_datetime.beginning_of_minute)) if force_from || use_from_boundary
        query = query.where(aggregated_arel_table[:started_at].lteq(to_datetime)) if to_datetime

        if grouped_by_values
          query = query.where(aggregated_arel_table[:grouped_by].eq(formated_grouped_by_values))
          query = query.group(group) if group
        elsif group
          query = query.group([group, aggregated_arel_table[:grouped_by]])
        else
          query = query.group(aggregated_arel_table[:grouped_by])
        end

        query = query.order(order) if order
        query.project(select).to_sql
      end

      def distinct_codes
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          ::Clickhouse::EventsEnrichedExpanded
            .where(external_subscription_id: subscription.external_id)
            .where(organization_id: subscription.organization.id)
            .where(timestamp: from_datetime..applicable_to_datetime)
            .pluck("DISTINCT(code)")
        end
      end

      def distinct_charge_filter_ids
        ::Clickhouse::EventsEnrichedExpanded
          .where(subscription_id: subscription.id)
          .where(organization_id: subscription.organization_id)
          .where(timestamp: from_datetime..to_datetime)
          .where.not(charge_filter_id: "")
          .pluck("DISTINCT(charge_filter_id)")
      end

      def events_values(limit: nil, force_from: false, exclude_event: false)
        Events::Stores::Utils::ClickhouseConnection.with_retry do
          scope = events(force_from:, ordered: true)

          if exclude_event && filters[:event].present?
            scope = scope.where.not(transaction_id: filters[:event].transaction_id)
          end

          scope = scope.limit(limit) if limit

          scope.pluck(:decimal_value)
        end
      end

      def prorated_events_values(total_duration)
        ratio_sql = Events::Stores::Utils::ClickhouseSqlHelpers.duration_ratio_sql(
          "events_enriched_expanded.timestamp", to_datetime, total_duration, timezone
        )

        Events::Stores::Utils::ClickhouseConnection.with_retry do
          events(ordered: true).pluck(Arel.sql("events_enriched_expanded.decimal_value * (#{ratio_sql})"))
        end
      end

      def last_event
        Events::Stores::Utils::ClickhouseConnection.with_retry { events(ordered: true).last }
      end

      def grouped_last_event
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            select: [
              arel_enriched_table[:grouped_by],
              arel_enriched_table[:decimal_value].as("property"),
              arel_enriched_table[:timestamp]
            ]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              DISTINCT ON (grouped_by) grouped_by,
              timestamp,
              property
            FROM events
            ORDER BY timestamp DESC
          SQL

          prepare_grouped_result(connection.select_all(sql).rows, timestamp: true)
        end
      end

      def count
        merge_aggregation("countMerge", :count_state, "total_count").to_i
      end

      def grouped_count
        grouped_merge_aggregation("countMerge", :count_state, "total_count")
      end

      # NOTE: check if an event created before the current on belongs to an active (as in present and not removed)
      #       unique property
      def active_unique_property?(event)
        previous_event = Events::Stores::Utils::ClickhouseConnection.with_retry do
          events.where(value: event.properties[aggregation_property])
            .where(timestamp: ...event.timestamp)
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
          query = Events::Stores::AggregatedClickhouse::UniqueCountQuery.new(store: self)
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
          query = Events::Stores::AggregatedClickhouse::UniqueCountQuery.new(store: self)

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
          query = Events::Stores::AggregatedClickhouse::UniqueCountQuery.new(store: self)
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
          query = Events::Stores::AggregatedClickhouse::UniqueCountQuery.new(store: self)
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
          query = Events::Stores::AggregatedClickhouse::UniqueCountQuery.new(store: self)
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
          query = Events::Stores::AggregatedClickhouse::UniqueCountQuery.new(store: self)
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
        merge_aggregation("maxMerge", :max_state, "max_value")
      end

      def grouped_max
        grouped_merge_aggregation("maxMerge", :max_state, "max_value")
      end

      def last
        merge_aggregation("argMaxMerge", :latest_state, "latest_value")
      end

      def grouped_last
        grouped_merge_aggregation("argMaxMerge", :latest_state, "latest_value")
      end

      def sum_precise_total_amount_cents
        merge_aggregation("sumMerge", :precise_total_amount_cents_sum_state, "sum_value")
      end

      def grouped_sum_precise_total_amount_cents
        grouped_merge_aggregation("sumMerge", :precise_total_amount_cents_sum_state, "sum_value")
      end

      def sum
        merge_aggregation("sumMerge", :sum_state, "sum_value")
      end

      def grouped_sum
        grouped_merge_aggregation("sumMerge", :sum_state, "sum_value")
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          Events::Stores::Utils::ClickhouseSqlHelpers.duration_ratio_sql(
            "events_enriched_expanded.timestamp", to_datetime, period_duration, timezone
          )
        end

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            select: [
              Arel::Nodes::InfixOperation.new(
                "*",
                arel_enriched_table[:decimal_value],
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
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          Events::Stores::Utils::ClickhouseSqlHelpers.duration_ratio_sql(
            "events_enriched_expanded.timestamp", to_datetime, period_duration, timezone
          )
        end

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          cte_sql = events_sql(
            select: [
              arel_enriched_table[:grouped_by],
              Arel::Nodes::InfixOperation.new(
                "*",
                arel_enriched_table[:decimal_value],
                Arel::Nodes::Grouping.new(Arel::Nodes::SqlLiteral.new(ratio.to_s))
              ).as("prorated_value")
            ]
          )

          sql = <<-SQL
            WITH events AS (#{cte_sql})

            SELECT
              events.grouped_by,
              sum(events.prorated_value)
            FROM events
            GROUP BY events.grouped_by
          SQL

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end

      def sum_date_breakdown
        date_field = Events::Stores::Utils::ClickhouseSqlHelpers.date_in_customer_timezone_sql(
          "events_aggregated.started_at", timezone
        )

        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = aggregated_events_sql(
            select: [
              Arel::Nodes::NamedFunction.new(
                "toDate",
                [Arel::Nodes::SqlLiteral.new(date_field)]
              ).as("day"),
              to_decimal128(Arel::Nodes::NamedFunction.new(
                "sumMerge",
                [aggregated_arel_table[:sum_state]]
              )).as("property")
            ],
            group: Arel::Nodes::SqlLiteral.new("day"),
            order: Arel::Nodes::SqlLiteral.new("day")
          )

          connection.select_all(Arel.sql(sql)).rows.map do |row|
            {date: row.first.to_date, value: row.last}
          end
        end
      end

      def weighted_sum(initial_value: 0)
        result = Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          query = Events::Stores::AggregatedClickhouse::WeightedSumQuery.new(store: self)

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
          query = AggregatedClickhouse::WeightedSumQuery.new(store: self)

          # NOTE: build the list from each group
          #       found in the events in the period
          formatted_initial_values = grouped_count.map do |group|
            {groups: group[:groups], value: 0}
          end

          # NOTE: fill the initial values for groups from previous period
          initial_values.each do |initial_value|
            group = formatted_initial_values.find { |g| g[:groups] == initial_value[:groups] }

            if group.present?
              group[:value] = initial_value[:value]
            else
              formatted_initial_values << initial_value
            end
          end
          return [] if formatted_initial_values.empty?

          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.grouped_query(initial_values: formatted_initial_values)),
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
          query = Events::Stores::AggregatedClickhouse::WeightedSumQuery.new(store: self)

          connection.select_all(
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
        end
      end

      def aggregated_arel_table
        @aggregated_arel_table ||= ::Clickhouse::EventsAggregated.arel_table
      end

      def arel_enriched_table
        @arel_enriched_table ||= ::Clickhouse::EventsEnrichedExpanded.arel_table
      end

      def formated_grouped_by_values
        # NOTE: grouped_by is populated from a sorted Map(String, String) converted into a String
        #       to make it comparable, we need to sort the group keys and replace nil values with "<nil>" string
        grouped_by_values
          .transform_values { |value| value || NIL_GROUP_VALUE }
          .sort_by { |key, _| key }
          .to_h
          .to_json(escape_html_entities: false) # to_json is escaping < and >, leading to invalid group keys when expecting "<nil>"
      end

      # NOTE: returns the values for each groups
      #       The result format will be an array of hash with the format:
      #       [{ groups: { 'cloud' => 'aws', 'region' => 'us_east_1' }, value: 12.9 }, ...]
      def prepare_grouped_result(rows, timestamp: false)
        rows.map do |row|
          event_timestamp = nil

          if timestamp
            group_by_string, event_timestamp, value = row
          else
            group_by_string, value = row
          end

          groups = group_by_string.transform_values! { |v| (v == NIL_GROUP_VALUE) ? nil : v }
          next unless groups.keys.sort == grouped_by.sort

          result = {
            groups: groups,
            value: value
          }

          result[:timestamp] = event_timestamp if timestamp

          result
        end
      end

      def to_decimal128(value)
        Arel::Nodes::NamedFunction.new(
          "toDecimal128",
          [
            value,
            DECIMAL_SCALE
          ]
        )
      end

      def cast_to_json(attribute)
        Arel::Nodes::SqlLiteral.new("#{attribute.relation.name}.#{attribute.name}::JSON")
      end

      def merge_aggregation(aggregation_type, column, as)
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = aggregated_events_sql(select: [
            to_decimal128(Arel::Nodes::NamedFunction.new(
              aggregation_type,
              [aggregated_arel_table[column]]
            )).as(as)
          ])

          connection.select_value(sql)
        end
      end

      def grouped_merge_aggregation(aggregation_type, column, as)
        Events::Stores::Utils::ClickhouseConnection.connection_with_retry do |connection|
          sql = aggregated_events_sql(select: [
            cast_to_json(aggregated_arel_table[:grouped_by]),
            to_decimal128(Arel::Nodes::NamedFunction.new(
              aggregation_type,
              [aggregated_arel_table[column]]
            )).as(as)
          ])

          prepare_grouped_result(connection.select_all(sql).rows)
        end
      end
    end
  end
end
