# frozen_string_literal: true

module Events
  module Stores
    class PostgresStore < BaseStore
      def events(force_from: false)
        scope = Event.where(external_subscription_id: subscription.external_id)
          .where(code:)
          .order(timestamp: :asc)

        if is_charge_group?
          package_count = find_usage_charge_group&.current_package_count
          scope = scope.where(current_package_count: package_count) if package_count
        end

        scope = scope.from_datetime(from_datetime) if force_from || use_from_boundary
        scope = scope.to_datetime(to_datetime) if to_datetime

        if numeric_property
          scope = scope.where(presence_condition)
            .where(numeric_condition)
        end

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

      def max
        events.maximum("(#{sanitized_propery_name})::numeric")
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

      def sanitized_propery_name
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['events.properties->>?', aggregation_property],
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

      private

      def is_charge_group?
        event.current_package_count.present?
      end

      def find_usage_charge_group
        plan = subscription.plan
        billable_metric = event.organization.billable_metrics.find_by(code: event.code)
        charge = Charge.where(plan:, billable_metric:).first

        UsageChargeGroup.find_by(subscription_id: subscription.id, charge_group_id: charge.charge_group_id)
      end
    end
  end
end
