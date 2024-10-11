# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseStore < BaseStore
      DECIMAL_SCALE = 26

      def events(force_from: false, ordered: false)
        scope = ::Clickhouse::EventsEnriched.where(external_subscription_id: subscription.external_id)
          .where(organization_id: subscription.organization.id)
          .where(code:)

        scope = scope.order(timestamp: :asc) if ordered

        scope = scope.where("events_enriched.timestamp >= ?", from_datetime) if force_from || use_from_boundary
        scope = scope.where("events_enriched.timestamp <= ?", to_datetime) if to_datetime
        scope = scope.limit_by(1, 'events_enriched.transaction_id')

        scope = with_grouped_by_values(scope) if grouped_by_values?
        filters_scope(scope)
      end

      def events_values(limit: nil, force_from: false, exclude_event: false)
        scope = events(force_from:, ordered: true)

        scope = scope.where("events_enriched.transaction_id != ?", filters[:event].transaction_id) if exclude_event
        scope = scope.limit(limit) if limit

        scope.pluck("events_enriched.decimal_value")
      end

      def last_event
        events(ordered: true).last
      end

      def grouped_last_event
        groups = grouped_by.map { |group| sanitized_property_name(group) }
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(", ")

        cte_sql = events(ordered: true)
          .select(Arel.sql(
            (groups.map.with_index { |group, index| "#{group} AS g_#{index}" } +
              ["events_enriched.decimal_value AS property", "events_enriched.timestamp"]).join(", ")
          ))
          .to_sql

        sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            DISTINCT ON (#{group_names}) #{group_names},
            events.timestamp,
            property
          FROM events
          ORDER BY #{group_names}, events.timestamp DESC
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows, timestamp: true)
      end

      def prorated_events_values(total_duration)
        ratio_sql = duration_ratio_sql("events_enriched.timestamp", to_datetime, total_duration)

        events(ordered: true).pluck(Arel.sql("events_enriched.decimal_value * (#{ratio_sql})"))
      end

      def count
        sql = <<-SQL
          WITH events AS (#{events.to_sql})

          SELECT count()
          FROM events
        SQL

        ::Clickhouse::EventsEnriched.connection.select_value(sql).to_i
      end

      def grouped_count
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }

        cte_sql = events
          .select((groups + ["events_enriched.transaction_id"]).join(", "))

        sql = <<-SQL
          WITH events AS (#{cte_sql.to_sql})

          SELECT
            #{group_names.join(", ")},
            toDecimal128(count(), #{DECIMAL_SCALE})
          FROM events
          GROUP BY #{group_names.join(",")}
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      # NOTE: check if an event created before the current on belongs to an active (as in present and not removed)
      #       unique property
      def active_unique_property?(event)
        previous_event = events
          .where("events_enriched.properties[?] = ?", aggregation_property, event.properties[aggregation_property])
          .where("events_enriched.timestamp < ?", event.timestamp)
          .order(timestamp: :desc)
          .first

        previous_event && (
          previous_event.properties["operation_type"].nil? ||
          previous_event.properties["operation_type"] == "add"
        )
      end

      def unique_count
        query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            sanitize_colon(query.query),
            {decimal_scale: DECIMAL_SCALE}
          ]
        )
        result = ::Clickhouse::EventsEnriched.connection.select_one(sql)

        result["aggregation"]
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def unique_count_breakdown
        query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
        ::Clickhouse::EventsEnriched.connection.select_all(
          ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              sanitize_colon(query.breakdown_query),
              {decimal_scale: DECIMAL_SCALE}
            ]
          )
        ).rows
      end

      def prorated_unique_count
        query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            sanitize_colon(query.prorated_query),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              decimal_scale: DECIMAL_SCALE,
              timezone: customer.applicable_timezone
            }
          ]
        )
        result = ::Clickhouse::EventsEnriched.connection.select_one(sql)

        result["aggregation"]
      end

      def prorated_unique_count_breakdown(with_remove: false)
        query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            sanitize_colon(query.prorated_breakdown_query(with_remove:)),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              decimal_scale: DECIMAL_SCALE,
              timezone: customer.applicable_timezone
            }
          ]
        )

        ::Clickhouse::EventsEnriched.connection.select_all(sql).to_a
      end

      def grouped_unique_count
        query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            sanitize_colon(query.grouped_query),
            {
              to_datetime: to_datetime.ceil,
              decimal_scale: DECIMAL_SCALE
            }
          ]
        )

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def grouped_prorated_unique_count
        query = Events::Stores::Clickhouse::UniqueCountQuery.new(store: self)
        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            sanitize_colon(query.grouped_prorated_query),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              decimal_scale: DECIMAL_SCALE,
              timezone: customer.applicable_timezone
            }
          ]
        )
        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def max
        sql = <<-SQL
          WITH events AS (#{events.to_sql})

          SELECT max(events.decimal_value)
          FROM events
        SQL

        ::Clickhouse::EventsEnriched.connection.select_value(sql)
      end

      def grouped_max
        groups = grouped_by.map { |group| sanitized_property_name(group) }
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(", ")

        cte_sql = events
          .select(Arel.sql(
            (groups.map.with_index { |group, index| "#{group} AS g_#{index}" } +
              ["events_enriched.decimal_value AS property", "events_enriched.timestamp"]).join(", ")
          ))
          .to_sql

        sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            #{group_names},
            MAX(property)
          FROM events
          GROUP BY #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def last
        value = events(ordered: true).last&.properties&.[](aggregation_property)
        return value unless value

        BigDecimal(value)
      end

      def grouped_last
        groups = grouped_by.map { |group| sanitized_property_name(group) }
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(", ")

        cte_sql = events(ordered: true)
          .select(Arel.sql(
            (groups.map.with_index { |group, index| "#{group} AS g_#{index}" } +
              ["events_enriched.decimal_value AS property", "events_enriched.timestamp"]).join(", ")
          ))
          .to_sql

        sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            DISTINCT ON (#{group_names}) #{group_names},
            property
          FROM events
          ORDER BY #{group_names}, events.timestamp DESC
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def sum_precise_total_amount_cents
        sql = <<-SQL
          WITH events AS (#{events.to_sql})

          SELECT SUM(events.precise_total_amount_cents)
          FROM events
        SQL

        ::Clickhouse::EventsEnriched.connection.select_value(sql)
      end

      def grouped_sum_precise_total_amount_cents
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(", ")

        cte_sql = events
          .select((groups + [Arel.sql("precise_total_amount_cents as property")]).join(", "))

        sql = <<-SQL
          WITH events AS (#{cte_sql.to_sql})

          SELECT
            #{group_names},
            sum(events.property)
          FROM events
          GROUP BY #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def sum
        sql = <<-SQL
          WITH events AS (#{events.to_sql})
          
          SELECT sum(events.decimal_value)
          FROM events
        SQL

        ::Clickhouse::EventsEnriched.connection.select_value(sql)
      end

      def grouped_sum
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(", ")

        cte_sql = events
          .select((groups + [Arel.sql("events_enriched.decimal_value AS property")]).join(", "))

        sql = <<-SQL
          WITH events AS (#{cte_sql.to_sql})

          SELECT
            #{group_names},
            sum(events.property)
          FROM events
          GROUP BY #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql("events_enriched.timestamp", to_datetime, period_duration)
        end

        cte_sql = events
          .select(Arel.sql("events_enriched.decimal_value * (#{ratio}) AS prorated_value"))
          .to_sql

        sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT sum(events.prorated_value)
          FROM events
        SQL

        ::Clickhouse::EventsEnriched.connection.select_value(sql)
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(", ")

        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql("events_enriched.timestamp", to_datetime, period_duration)
        end

        cte_sql = events
          .select((groups + [Arel.sql("events_enriched.decimal_value * (#{ratio}) AS prorated_value")]).join(", "))
          .to_sql

        sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            #{group_names},
            sum(events.prorated_value)
          FROM events
          GROUP BY #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      def sum_date_breakdown
        date_field = date_in_customer_timezone_sql("events_enriched.timestamp")

        cte_sql = events
          .select("toDate(#{date_field}) as day, events_enriched.decimal_value AS property")
          .to_sql

        sql = <<-SQL
          WITH events AS (#{cte_sql})

          SELECT
            events.day,
            sum(events.property) AS day_sum
          FROM events
          GROUP BY events.day
          ORDER BY events.day asc
        SQL

        ::Clickhouse::EventsEnriched.connection.select_all(Arel.sql(sql)).rows.map do |row|
          {date: row.first.to_date, value: row.last}
        end
      end

      def weighted_sum(initial_value: 0)
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

        result = ::Clickhouse::EventsEnriched.connection.select_one(sql)
        result["aggregation"]
      end

      def grouped_weighted_sum(initial_values: [])
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

        prepare_grouped_result(::Clickhouse::EventsEnriched.connection.select_all(sql).rows)
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def weighted_sum_breakdown(initial_value: 0)
        query = Events::Stores::Clickhouse::WeightedSumQuery.new(store: self)

        ::Clickhouse::EventsEnriched.connection.select_all(
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
        sql = conditions.map { "(#{_1})" }.join(" OR ")
        scope = scope.where.not(sql) if sql.present?

        scope
      end

      def with_grouped_by_values(scope)
        grouped_by_values.each do |grouped_by, grouped_by_value|
          scope = if grouped_by_value.present?
            scope.where("events_enriched.properties[?] = ?", grouped_by, grouped_by_value)
          else
            scope.where("COALESCE(events_enriched.properties[?], '') = ''", grouped_by)
          end
        end

        scope
      end

      def sanitized_property_name(property = aggregation_property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ["events_enriched.properties[?]", property]
        )
      end

      def date_in_customer_timezone_sql(date)
        sql = if date.is_a?(String)
          "toTimezone(#{date}, :timezone)"
        else
          "toTimezone(toDateTime64(:date, 5, 'UTC'), :timezone)"
        end

        ActiveRecord::Base.sanitize_sql_for_conditions(
          [sql, {date:, timezone: customer.applicable_timezone}]
        )
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to, duration)
        from_in_timezone = date_in_customer_timezone_sql(from)
        to_in_timezone = date_in_customer_timezone_sql(to)

        "(date_diff('days', #{from_in_timezone}, #{to_in_timezone}) + 1) / #{duration}"
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
    end
  end
end
