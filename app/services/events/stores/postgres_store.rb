# frozen_string_literal: true

module Events
  module Stores
    class PostgresStore < BaseStore
      def events(force_from: false, ordered: false)
        scope = Event.where(external_subscription_id: subscription.external_id)
          .where(organization_id: subscription.organization.id)
          .where(code:)

        scope = scope.order(timestamp: :asc) if ordered

        scope = scope.from_datetime(from_datetime) if force_from || use_from_boundary
        scope = scope.to_datetime(applicable_to_datetime) if applicable_to_datetime

        if numeric_property
          scope = scope.where(presence_condition)
            .where(numeric_condition)
        end

        scope = apply_grouped_by_values(scope) if grouped_by_values?
        filters_scope(scope)
      end

      def distinct_codes
        Event.where(external_subscription_id: subscription.external_id)
          .where(organization_id: subscription.organization.id)
          .from_datetime(from_datetime)
          .to_datetime(applicable_to_datetime)
          .pluck("DISTINCT(code)")
      end

      def distinct_charges_and_filters
        EnrichedEvent.where(organization_id: subscription.organization_id)
          .where(subscription_id: subscription.id)
          .where(timestamp: from_datetime..to_datetime)
          .distinct
          .pluck(:charge_id, :charge_filter_id)
      end

      def events_values(limit: nil, force_from: false, exclude_event: false)
        field_name = sanitized_property_name
        field_name = "(#{field_name})::numeric" if numeric_property

        scope = events(force_from:, ordered: true)
        scope = scope.where.not(transaction_id: filters[:event].transaction_id) if exclude_event
        scope = scope.limit(limit) if limit

        scope.pluck(Arel.sql(field_name))
      end

      def last_event
        events(ordered: true).last
      end

      def grouped_last_event
        groups = sanitized_grouped_by

        sql = events
          .order(Arel.sql((groups + ["events.timestamp DESC, created_at DESC"]).join(", ")))
          .select(
            [
              "DISTINCT ON (#{groups.join(", ")}) #{groups.join(", ")}",
              "events.timestamp",
              "(#{sanitized_property_name})::numeric AS value"
            ].join(", ")
          )
          .to_sql

        prepare_grouped_result(select_all(sql).rows, timestamp: true)
      end

      def prorated_events_values(total_duration)
        ratio_sql = duration_ratio_sql("events.timestamp", to_datetime, total_duration)

        events(ordered: true).pluck(Arel.sql("(#{sanitized_property_name})::numeric * (#{ratio_sql})::numeric"))
      end

      def grouped_count
        results = events
          .group(sanitized_grouped_by)
          .count
          .map { |group, value| [group, value].flatten }

        prepare_grouped_result(results)
      end

      # NOTE: check if an event created before the current on belongs to an active (as in present and not removed)
      #       unique property
      def active_unique_property?(event)
        previous_event = events.where.not(id: event.id)
          .where("events.properties @> ?", {aggregation_property => event.properties[aggregation_property]}.to_json)
          .where("events.timestamp < ?", event.timestamp)
          .order(timestamp: :desc)
          .first

        previous_event && (
          previous_event.properties["operation_type"].nil? ||
          previous_event.properties["operation_type"] == "add"
        )
      end

      def unique_count
        query = Events::Stores::Postgres::UniqueCountQuery.new(store: self)
        sql = sanitize_sql_for_conditions([query.query])
        result = select_one(sql)

        result["aggregation"]
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def unique_count_breakdown
        query = Events::Stores::Postgres::UniqueCountQuery.new(store: self)
        select_all(
          sanitize_sql_for_conditions([query.breakdown_query])
        ).rows
      end

      def prorated_unique_count
        query = Events::Stores::Postgres::UniqueCountQuery.new(store: self)
        sql = sanitize_sql_for_conditions(
          [
            sanitize_colon(query.prorated_query),
            {
              from_datetime:,
              to_datetime:,
              timezone: customer.applicable_timezone
            }
          ]
        )
        result = select_one(sql)

        result["aggregation"]
      end

      def prorated_unique_count_breakdown(with_remove: false)
        query = Events::Stores::Postgres::UniqueCountQuery.new(store: self)
        sql = sanitize_sql_for_conditions(
          [
            sanitize_colon(query.prorated_breakdown_query(with_remove:)),
            {
              from_datetime:,
              to_datetime:,
              timezone: customer.applicable_timezone
            }
          ]
        )
        select_all(sql).to_a
      end

      def grouped_unique_count
        query = Events::Stores::Postgres::UniqueCountQuery.new(store: self)

        sql = sanitize_sql_for_conditions(
          [query.grouped_query]
        )

        prepare_grouped_result(select_all(sql).rows)
      end

      def grouped_prorated_unique_count
        query = Events::Stores::Postgres::UniqueCountQuery.new(store: self)
        sql = sanitize_sql_for_conditions(
          [
            sanitize_colon(query.grouped_prorated_query),
            {
              from_datetime:,
              to_datetime:,
              timezone: customer.applicable_timezone
            }
          ]
        )
        prepare_grouped_result(select_all(sql).rows)
      end

      def max
        events.maximum("(#{sanitized_property_name})::numeric")
      end

      def grouped_max
        results = events
          .group(sanitized_grouped_by)
          .maximum("(#{sanitized_property_name})::numeric")
          .map { |group, value| [group, value].flatten }

        prepare_grouped_result(results)
      end

      def last
        events.order(timestamp: :desc, created_at: :desc).first&.properties&.[](aggregation_property)
      end

      def grouped_last
        groups = sanitized_grouped_by

        sql = events
          .order(Arel.sql((groups + ["events.timestamp DESC, created_at DESC"]).join(", ")))
          .select(
            "DISTINCT ON (#{groups.join(", ")}) #{groups.join(", ")}, (#{sanitized_property_name})::numeric AS value"
          )
          .to_sql

        prepare_grouped_result(select_all(sql).rows)
      end

      def sum_precise_total_amount_cents
        events.sum(:precise_total_amount_cents)
      end

      def grouped_sum_precise_total_amount_cents
        results = events
          .group(sanitized_grouped_by)
          .sum(:precise_total_amount_cents)
          .map { |group, value| [group, value].flatten }

        prepare_grouped_result(results)
      end

      def sum
        events.sum("(#{sanitized_property_name})::numeric")
      end

      def grouped_sum
        results = events
          .group(sanitized_grouped_by)
          .sum("(#{sanitized_property_name})::numeric")
          .map { |group, value| [group, value].flatten }

        prepare_grouped_result(results)
      end

      def presentation_breakdown_sum
        presentation_breakdown(aggregation_sql: "SUM((#{sanitized_property_name})::numeric)")
      end

      def presentation_breakdown_count
        presentation_breakdown(aggregation_sql: "COUNT(*)")
      end

      def presentation_breakdown_latest
        rows = if grouped_and_presentation_columns[:grouped_by].any?
          sql = events
            .order(Arel.sql((sanitized_grouped_by + ["events.timestamp DESC, events.created_at DESC"]).join(", ")))
            .select(
              [
                "DISTINCT ON (#{sanitized_grouped_by.join(", ")}) #{sanitized_grouped_by_and_presentation_by.join(", ")}",
                "(#{sanitized_property_name})::numeric"
              ].join(", ")
            )
            .to_sql

          select_all(sql).rows
        else
          events
            .order(timestamp: :desc, created_at: :desc)
            .limit(1)
            .pluck(Arel.sql((sanitized_grouped_by_and_presentation_by + ["(#{sanitized_property_name})::numeric"]).join(", ")))
        end

        prepare_presentation_result(rows)
      end

      def presentation_breakdown_max
        rows = if grouped_and_presentation_columns[:grouped_by].any?
          sql = events
            .order(Arel.sql((sanitized_grouped_by + ["(#{sanitized_property_name})::numeric DESC"]).join(", ")))
            .select(
              [
                "DISTINCT ON (#{sanitized_grouped_by.join(", ")}) #{sanitized_grouped_by_and_presentation_by.join(", ")}",
                "(#{sanitized_property_name})::numeric"
              ].join(", ")
            )
            .to_sql

          select_all(sql).rows
        else
          events
            .order(Arel.sql("(#{sanitized_property_name})::numeric DESC"))
            .limit(1)
            .pluck(Arel.sql((sanitized_grouped_by_and_presentation_by + ["(#{sanitized_property_name})::numeric"]).join(", ")))
        end

        prepare_presentation_result(rows)
      end

      def presentation_breakdown_unique_count
        # NOTE: Important to use a dup to avoid mutate the current object grouped_by using presentation_by values
        # also, set presentation_by to nil to avoid any confusion in the query building
        unique_store_for_breakdown = dup
        unique_store_for_breakdown.grouped_by = grouped_and_presentation_columns.values.flatten
        unique_store_for_breakdown.presentation_by = nil

        query = Events::Stores::Postgres::UniqueCountQuery.new(store: unique_store_for_breakdown)

        sql = sanitize_sql_for_conditions(
          [query.grouped_query]
        )

        prepare_presentation_result(select_all(sql).rows)
      end

      def presentation_breakdown_weighted_sum(initial_value: 0, initial_values: [])
        # NOTE: Important to use a dup to avoid mutate the current object grouped_by using presentation_by values
        # also, set presentation_by to nil to avoid any confusion in the query building
        weighted_sum_store_for_breakdown = dup
        weighted_sum_store_for_breakdown.grouped_by = grouped_and_presentation_columns.values.flatten
        weighted_sum_store_for_breakdown.presentation_by = nil

        query = Events::Stores::Postgres::WeightedSumQuery.new(store: weighted_sum_store_for_breakdown)

        baseline_initial_values = if initial_values.present?
          initial_values
        elsif initial_value.to_d.nonzero?
          [{groups: {}, value: initial_value}]
        else
          []
        end

        formatted_initial_values = weighted_sum_store_for_breakdown.formatted_weighted_sum_initial_values(baseline_initial_values)
        return [] if formatted_initial_values.empty?

        sql = sanitize_sql_for_conditions(
          [
            sanitize_colon(query.grouped_query(initial_values: formatted_initial_values)),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil
            }
          ]
        )

        prepare_presentation_result(select_all(sql).rows)
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql("events.timestamp", to_datetime, period_duration)
        end

        sql = <<-SQL
          SUM(
            (#{sanitized_property_name})::numeric * (#{ratio})::numeric
          ) AS sum_result
        SQL

        connection.execute(Arel.sql(events.select(sql).to_sql)).first["sum_result"]
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql("events.timestamp", to_datetime, period_duration)
        end

        sum_sql = <<-SQL
          #{sanitized_grouped_by.join(", ")},
          SUM(
            (#{sanitized_property_name})::numeric * (#{ratio})::numeric
          ) AS sum_result
        SQL

        sql = events
          .group(sanitized_grouped_by)
          .select(sum_sql)
          .to_sql

        prepare_grouped_result(select_all(sql).rows)
      end

      def sum_date_breakdown
        date_field = ::Utils::Timezone.date_in_customer_timezone_sql(customer, "events.timestamp")

        events.group(Arel.sql("DATE(#{date_field})"))
          .order(Arel.sql("DATE(#{date_field}) ASC"))
          .pluck(Arel.sql("DATE(#{date_field}) AS date, SUM((#{sanitized_property_name})::numeric)"))
          .map do |row|
            {date: row.first.to_date, value: row.last}
          end
      end

      def weighted_sum(initial_value: 0)
        query = Events::Stores::Postgres::WeightedSumQuery.new(store: self)

        sql = sanitize_sql_for_conditions(
          [
            sanitize_colon(query.query),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              initial_value: initial_value || 0
            }
          ]
        )

        result = select_one(sql)
        result["aggregation"]
      end

      def grouped_weighted_sum(initial_values: [])
        query = Events::Stores::Postgres::WeightedSumQuery.new(store: self)

        formatted_initial_values = formatted_weighted_sum_initial_values(initial_values)
        return [] if formatted_initial_values.empty?

        sql = sanitize_sql_for_conditions(
          [
            sanitize_colon(query.grouped_query(initial_values: formatted_initial_values)),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil
            }
          ]
        )

        prepare_grouped_result(select_all(sql).rows)
      end

      def formatted_weighted_sum_initial_values(initial_values)
        # NOTE: build the list of initial values for each groups
        #       from the events in the period
        formatted_initial_values = grouped_count.map do |group|
          value = 0
          previous_group = initial_values.find { |g| g[:groups] == group[:groups] }
          value = previous_group[:value] if previous_group
          {groups: group[:groups], value:}
        end

        # NOTE: add the initial values for groups that are not in the events
        initial_values.each do |initial_value|
          next if formatted_initial_values.find { |g| g[:groups] == initial_value[:groups] }

          formatted_initial_values << initial_value
        end

        formatted_initial_values
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def weighted_sum_breakdown(initial_value: 0)
        query = Events::Stores::Postgres::WeightedSumQuery.new(store: self)
        select_all(
          sanitize_sql_for_conditions(
            [
              sanitize_colon(query.breakdown_query),
              {
                from_datetime:,
                to_datetime: to_datetime.ceil,
                initial_value: initial_value || 0
              }
            ]
          )
        ).rows
      end

      def filters_scope(scope)
        matching_filters.each do |key, values|
          scope = scope.where(
            "events.properties ->> ? IN (?)",
            key.to_s,
            values.map(&:to_s)
          )
        end

        conditions = ignored_filters.map do |filters|
          filters.map do |key, values|
            sanitize_sql_for_conditions(
              ["(coalesce(events.properties ->> ?, '') IN (?))", key.to_s, values.map(&:to_s)]
            )
          end.join(" AND ")
        end
        sql = conditions.compact_blank.map { "(#{it})" }.join(" OR ")
        scope = scope.where.not(sql) if sql.present?

        scope
      end

      def apply_grouped_by_values(scope)
        grouped_by_values.each do |grouped_by, grouped_by_value|
          scope = if grouped_by_value.present?
            scope.where("events.properties @> ?", {grouped_by.to_s => grouped_by_value.to_s}.to_json)
          else
            scope.where(
              sanitize_sql_for_conditions(["COALESCE(events.properties->>?, '') = ''", grouped_by])
            )
          end
        end

        scope
      end

      def sanitized_property_name(property = aggregation_property)
        sanitize_sql_for_conditions(
          ["events.properties->>?", property]
        )
      end

      def presence_condition
        "events.properties::jsonb ? '#{sanitize_sql_for_conditions(aggregation_property)}'"
      end

      def numeric_condition
        # NOTE: ensure property value is a numeric value
        "#{sanitized_property_name} ~ '^-?\\d+(\\.\\d+)?$'"
      end

      def sanitized_grouped_by
        grouped_by.map { sanitized_property_name(it) }
      end

      def sanitized_grouped_by_and_presentation_by
        grouped_and_presentation_columns.values.flatten.map { |c| sanitized_property_name(c) }
      end

      delegate :connection, to: :Event

      delegate :select_all, to: :connection
      delegate :select_one, to: :connection

      delegate :sanitize_sql_for_conditions, to: :"ActiveRecord::Base"

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to, duration)
        from_in_timezone = ::Utils::Timezone.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = ::Utils::Timezone.date_in_customer_timezone_sql(customer, to)

        "((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}))::numeric + 1) / #{duration}::numeric"
      end

      # NOTE: returns the values for each groups
      #       The result format will be an array of hash with the format:
      #       [{ groups: { 'cloud' => 'aws', 'region' => 'us_east_1' }, value: 12.9 }, ...]
      def prepare_grouped_result(rows, timestamp: false)
        rows.map do |row|
          last_group = timestamp ? -2 : -1
          groups = row[...last_group].map(&:presence)

          result = {
            groups: grouped_by.each_with_object({}).with_index { |(g, r), i| r.merge!(g => groups[i]) },
            value: row.last
          }

          result[:timestamp] = row[-2] if timestamp

          result
        end
      end

      def prepare_presentation_result(rows)
        grouped_by_count = grouped_and_presentation_columns[:grouped_by].size
        presentation_by_count = grouped_and_presentation_columns[:presentation_by].size

        outer_map = {}

        rows.each do |row|
          grouped_attrs = {}
          grouped_and_presentation_columns[:grouped_by].each_with_index do |field, i|
            grouped_attrs[field] = row[i]
          end

          presentation_attrs = {}
          grouped_and_presentation_columns[:presentation_by].each_with_index do |field, i|
            presentation_attrs[field] = row[grouped_by_count + i]
          end

          units = row[grouped_by_count + presentation_by_count]

          result = outer_map[grouped_attrs.hash] ||= {groups: grouped_attrs, breakdowns: []}
          result[:breakdowns] << {presentation_by: presentation_attrs, units: units}
        end

        outer_map.values
      end

      def presentation_breakdown(aggregation_sql:)
        rows = events.group(sanitized_grouped_by_and_presentation_by).pluck(Arel.sql((sanitized_grouped_by_and_presentation_by + [aggregation_sql]).join(", ")))

        prepare_presentation_result(rows)
      end

      def grouped_and_presentation_columns
        @grouped_and_presentation_columns ||= {grouped_by: grouped_by || [], presentation_by: presentation_by.difference(grouped_by || [])}
      end

      def operation_type_sql
        "COALESCE(events.properties->>'operation_type', 'add')"
      end

      def created_at_ordering_column
        "events.created_at"
      end
    end
  end
end
