# frozen_string_literal: true

module Events
  module Stores
    class ClickhouseStore < BaseStore
      DECIMAL_SCALE = 26
      DEDUPLICATION_GROUP = 'events_raw.transaction_id, events_raw.properties, events_raw.timestamp'

      # NOTE: keeps in mind that events could contains duplicated transaction_id
      #       and should be deduplicated depending on the aggregation logic
      def events(force_from: false)
        scope = ::Clickhouse::EventsRaw.where(external_subscription_id: subscription.external_id)
          .where(organization_id: subscription.organization.id)
          .where(code:)
          .order(timestamp: :asc)

        # TODO: check how to deal with this since events are not stored forever in clickhouse
        scope = scope.where('events_raw.timestamp >= ?', from_datetime) if force_from || use_from_boundary
        scope = scope.where('events_raw.timestamp <= ?', to_datetime) if to_datetime
        scope = scope.where(numeric_condition) if numeric_property

        scope = with_grouped_by_values(scope) if grouped_by_values?

        return scope unless group

        group_scope(scope)
      end

      def events_values(limit: nil, force_from: false)
        scope = events(force_from:).group(DEDUPLICATION_GROUP)

        scope = scope.limit(limit) if limit

        scope.pluck(Arel.sql(sanitized_numeric_property))
      end

      def last_event
        events.last
      end

      def grouped_last_event
        groups = grouped_by.map { |group| sanitized_property_name(group) }
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(', ')

        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select(Arel.sql(
            (groups.map.with_index { |group, index| "#{group} AS g_#{index}" } +
            ["#{sanitized_numeric_property} AS property", 'events_raw.timestamp']).join(', '),
          ))
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select
            DISTINCT ON (#{group_names}) #{group_names},
            events.timestamp,
            property
          from events
          ORDER BY #{group_names}, events.timestamp DESC
        SQL

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows, timestamp: true)
      end

      def prorated_events_values(total_duration)
        ratio_sql = duration_ratio_sql('events_raw.timestamp', to_datetime, total_duration)

        events.group(DEDUPLICATION_GROUP)
          .pluck(Arel.sql("#{sanitized_numeric_property} * (#{ratio_sql})"))
      end

      def count
        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select('COUNT(events_raw.transaction_id) as transaction_count')
          .group(:transaction_id)
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select
            COUNT(events.transaction_count) AS events_count
          from events
        SQL

        ::Clickhouse::EventsRaw.connection.select_value(sql).to_i
      end

      def grouped_count
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }

        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select((groups + ['events_raw.transaction_id']).join(', '))

        sql = <<-SQL
          with events as (#{cte_sql.to_sql})

          select
            #{group_names.join(', ')},
            toDecimal128(count(), #{DECIMAL_SCALE})
          from events
          group by #{group_names.join(',')}
        SQL

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows)
      end

      def max
        events.maximum(Arel.sql(sanitized_numeric_property))
      end

      def grouped_max
        groups = grouped_by.map { |group| sanitized_property_name(group) }
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(', ')

        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select(Arel.sql(
            (groups.map.with_index { |group, index| "#{group} AS g_#{index}" } +
            ["#{sanitized_numeric_property} AS property", 'events_raw.timestamp']).join(', '),
          ))
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select
            #{group_names},
            MAX(property)
          from events
          group by #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows)
      end

      def last
        value = events.last&.properties&.[](aggregation_property)
        return value unless value

        BigDecimal(value)
      end

      def grouped_last
        groups = grouped_by.map { |group| sanitized_property_name(group) }
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(', ')

        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select(Arel.sql(
            (groups.map.with_index { |group, index| "#{group} AS g_#{index}" } +
            ["#{sanitized_numeric_property} AS property", 'events_raw.timestamp']).join(', '),
          ))
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select
            DISTINCT ON (#{group_names}) #{group_names},
            property
          from events
          ORDER BY #{group_names}, events.timestamp DESC
        SQL

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows)
      end

      def sum
        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select(Arel.sql("#{sanitized_numeric_property} AS property"))
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select sum(events.property)
          from events
        SQL

        ::Clickhouse::EventsRaw.connection.select_value(sql)
      end

      def grouped_sum
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(', ')

        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select((groups + [Arel.sql("#{sanitized_numeric_property} AS property")]).join(', '))

        sql = <<-SQL
          with events as (#{cte_sql.to_sql})

          select
            #{group_names},
            sum(events.property)
          from events
          group by #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows)
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql('events_raw.timestamp', to_datetime, period_duration)
        end

        cte_sql = events
          .reorder('')
          .group(DEDUPLICATION_GROUP)
          .select(Arel.sql("(#{sanitized_numeric_property}) * (#{ratio}) AS prorated_value"))
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select sum(events.prorated_value)
          from events
        SQL

        ::Clickhouse::EventsRaw.connection.select_value(sql)
      end

      def grouped_prorated_sum(period_duration:, persisted_duration: nil)
        groups = grouped_by.map.with_index do |group, index|
          "#{sanitized_property_name(group)} AS g_#{index}"
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(', ')

        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql('events_raw.timestamp', to_datetime, period_duration)
        end

        cte_sql = events
          .reorder('')
          .group(DEDUPLICATION_GROUP)
          .select((groups + [Arel.sql("(#{sanitized_numeric_property}) * (#{ratio}) AS prorated_value")]).join(', '))
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select
            #{group_names},
            sum(events.prorated_value)
          from events
          group by #{group_names}
        SQL

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows)
      end

      def sum_date_breakdown
        date_field = date_in_customer_timezone_sql('events_raw.timestamp')

        cte_sql = events.group(DEDUPLICATION_GROUP)
          .select("toDate(#{date_field}) as day, #{sanitized_numeric_property} as property")
          .to_sql

        sql = <<-SQL
          with events as (#{cte_sql})

          select
            events.day,
            sum(events.property) as day_sum
          from events
          group by events.day
          order by events.day asc
        SQL

        ::Clickhouse::EventsRaw.connection.select_all(Arel.sql(sql)).rows.map do |row|
          { date: row.first.to_date, value: row.last }
        end
      end

      def weighted_sum(initial_value: 0)
        query = Events::Stores::Clickhouse::WeightedSumQuery.new(store: self)

        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            query.query,
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              decimal_scale: DECIMAL_SCALE,
              initial_value: initial_value || 0,
            },
          ],
        )

        result = ::Clickhouse::EventsRaw.connection.select_one(sql)
        result['aggregation']
      end

      def grouped_weighted_sum(initial_values: [])
        query = Clickhouse::WeightedSumQuery.new(store: self)

        # NOTE: build the list of initial values for each groups
        #       from the events in the period
        formated_initial_values = grouped_count.map do |group|
          value = 0
          previous_group = initial_values.find { |g| g[:groups] == group[:groups] }
          value = previous_group[:value] if previous_group
          { groups: group[:groups], value: }
        end

        # NOTE: add the initial values for groups that are not in the events
        initial_values.each do |intial_value|
          next if formated_initial_values.find { |g| g[:groups] == intial_value[:groups] }

          formated_initial_values << intial_value
        end
        return [] if formated_initial_values.empty?

        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            query.grouped_query(initial_values: formated_initial_values),
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              decimal_scale: DECIMAL_SCALE,
            },
          ],
        )

        prepare_grouped_result(::Clickhouse::EventsRaw.connection.select_all(sql).rows)
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def weighted_sum_breakdown(initial_value: 0)
        query = Events::Stores::Clickhouse::WeightedSumQuery.new(store: self)

        ::Clickhouse::EventsRaw.connection.select_all(
          ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              query.breakdown_query,
              {
                from_datetime:,
                to_datetime: to_datetime.ceil,
                decimal_scale: DECIMAL_SCALE,
                initial_value: initial_value || 0,
              },
            ],
          ),
        ).rows
      end

      def group_scope(scope)
        scope = scope.where('events_raw.properties[?] = ?', group.key.to_s, group.value.to_s)
        return scope unless group.parent

        scope.where('events_raw.properties[?] = ?', group.parent.key.to_s, group.parent.value.to_s)
      end

      def with_grouped_by_values(scope)
        grouped_by_values.each do |grouped_by, grouped_by_value|
          scope = scope.where('events_raw.properties[?] = ?', grouped_by, grouped_by_value)
        end

        scope
      end

      def sanitized_property_name(property = aggregation_property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['events_raw.properties[?]', property],
        )
      end

      def numeric_condition
        ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            'toDecimal128OrNull(events_raw.properties[?], ?) IS NOT NULL',
            aggregation_property,
            DECIMAL_SCALE,
          ],
        )
      end

      def sanitized_numeric_property
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['toDecimal128(events_raw.properties[?], ?)', aggregation_property, DECIMAL_SCALE],
        )
      end

      def date_in_customer_timezone_sql(date)
        sql = if date.is_a?(String)
          "toTimezone(#{date}, :timezone)"
        else
          "toTimezone(toDateTime64(:date, 5, 'UTC'), :timezone)"
        end

        ActiveRecord::Base.sanitize_sql_for_conditions(
          [sql, { date:, timezone: customer.applicable_timezone }],
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
            value: row.last,
          }

          result[:timestamp] = row[-2] if timestamp

          result
        end
      end
    end
  end
end
