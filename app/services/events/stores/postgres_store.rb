# frozen_string_literal: true

module Events
  module Stores
    class PostgresStore < BaseStore
      def events(force_from: false)
        scope = Event.where(external_subscription_id: subscription.external_id)
          .where(code:)
          .order(timestamp: :asc)

        scope = scope.from_datetime(from_datetime) if force_from || use_from_boundary
        scope = scope.to_datetime(to_datetime) if to_datetime

        if numeric_property
          scope = scope.where(presence_condition)
            .where(numeric_condition)
        end

        scope = with_grouped_by_values(scope) if grouped_by_values?

        return scope unless group

        group_scope(scope)
      end

      def events_values(limit: nil, force_from: false)
        field_name = sanitized_propery_name
        field_name = "(#{field_name})::numeric" if numeric_property

        scope = events(force_from:)
        scope = scope.limit(limit) if limit

        scope.pluck(Arel.sql(field_name))
      end

      def last_event
        events.last
      end

      def prorated_events_values(total_duration)
        ratio_sql = duration_ratio_sql('events.timestamp', to_datetime, total_duration)

        events.pluck(Arel.sql("(#{sanitized_propery_name})::numeric * (#{ratio_sql})::numeric"))
      end

      def grouped_count
        events
          .reorder(nil)
          .group(grouped_by.map { |group| sanitized_propery_name(group) })
          .count
          .map { |group, value| { group: [group].flatten, value: } }
      end

      def max
        events.maximum("(#{sanitized_propery_name})::numeric")
      end

      def grouped_max
        events
          .reorder(nil)
          .group(grouped_by.map { |group| sanitized_propery_name(group) })
          .maximum("(#{sanitized_propery_name})::numeric")
          .map { |group, value| { group: [group].flatten, value: } }
      end

      def last
        events.reorder(timestamp: :desc, created_at: :desc).first&.properties&.[](aggregation_property)
      end

      def sum
        events.sum("(#{sanitized_propery_name})::numeric")
      end

      def prorated_sum(period_duration:, persisted_duration: nil)
        ratio = if persisted_duration
          persisted_duration.fdiv(period_duration)
        else
          duration_ratio_sql('events.timestamp', to_datetime, period_duration)
        end

        sql = <<-SQL
          SUM(
            (#{sanitized_propery_name})::numeric * (#{ratio})::numeric
          ) AS sum_result
        SQL

        ActiveRecord::Base.connection.execute(
          Arel.sql(
            events.reorder('').select(sql).to_sql,
          ),
        ).first['sum_result']
      end

      def sum_date_breakdown
        date_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'events.timestamp')

        events.group(Arel.sql("DATE(#{date_field})"))
          .reorder(Arel.sql("DATE(#{date_field}) ASC"))
          .pluck(Arel.sql("DATE(#{date_field}) AS date, SUM((#{sanitized_propery_name})::numeric)"))
          .map do |row|
            { date: row.first.to_date, value: row.last }
          end
      end

      def weighted_sum(initial_value: 0)
        query = Events::Stores::Postgres::WeightedSumQuery.new(store: self)

        sql = ActiveRecord::Base.sanitize_sql_for_conditions(
          [
            query.query,
            {
              from_datetime:,
              to_datetime: to_datetime.ceil,
              initial_value: initial_value || 0,
            },
          ],
        )

        result = ActiveRecord::Base.connection.select_one(sql)
        result['aggregation']
      end

      # NOTE: not used in production, only for debug purpose to check the computed values before aggregation
      def weighted_sum_breakdown(initial_value: 0)
        query = Events::Stores::Postgres::WeightedSumQuery.new(store: self)
        ActiveRecord::Base.connection.select_all(
          ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              query.breakdown_query,
              {
                from_datetime:,
                to_datetime: to_datetime.ceil,
                initial_value: initial_value || 0,
              },
            ],
          ),
        ).rows
      end

      def group_scope(scope)
        scope = scope.where('events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return scope unless group.parent

        scope.where('events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      def with_grouped_by_values(scope)
        grouped_by_values.each do |grouped_by, grouped_by_value|
          scope = scope.where('events.properties @> ?', { grouped_by.to_s => grouped_by_value.to_s }.to_json)
        end

        scope
      end

      def sanitized_propery_name(property = aggregation_property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['events.properties->>?', property],
        )
      end

      def presence_condition
        "events.properties::jsonb ? '#{ActiveRecord::Base.sanitize_sql_for_conditions(aggregation_property)}'"
      end

      def numeric_condition
        # NOTE: ensure property value is a numeric value
        "#{sanitized_propery_name} ~ '^-?\\d+(\\.\\d+)?$'"
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to, duration)
        from_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, to)

        "((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}))::numeric + 1) / #{duration}::numeric"
      end
    end
  end
end
