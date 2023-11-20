# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class RecurringCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        result.aggregation = compute_aggregation.ceil(5)
        result.count = result.aggregation
        result.options = options
        result
      end

      def breakdown
        breakdown = persisted_breakdown
        breakdown += added_breakdown
        breakdown += removed_breadown
        breakdown += added_and_removed_breakdown

        # NOTE: in the breakdown, dates are in customer timezone
        result.breakdown = breakdown.sort_by(&:date)
        result
      end

      private

      def from_date_in_customer_timezone
        from_datetime.in_time_zone(customer.applicable_timezone).to_date
      end

      def to_date_in_customer_timezone
        to_datetime.in_time_zone(customer.applicable_timezone).to_date
      end

      def compute_aggregation
        ActiveRecord::Base.connection.execute(aggregation_query).first['aggregation_result']
      end

      def aggregation_query
        queries = [
          # NOTE: Billed on the full period
          persisted.select("SUM(#{persisted_pro_rata}::numeric)").to_sql,

          # NOTE: Added during the period
          added.select(duration_ratio_sql('quantified_events.added_at', to_datetime)).to_sql,

          # NOTE: removed during the period
          removed.select(duration_ratio_sql(from_datetime, 'quantified_events.removed_at')).to_sql,

          # NOTE: Added and then removed during the period
          added_and_removed.select(
            duration_ratio_sql(
              'quantified_events.added_at',
              'quantified_events.removed_at',
            ),
          ).to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      def base_scope
        quantified_events = QuantifiedEvent
          .where(organization_id: billable_metric.organization_id)
          .where(billable_metric_id: billable_metric.id)
          .where(external_subscription_id: subscription.external_id)

        return quantified_events unless group

        quantified_events = quantified_events.where('properties @> ?', { group.key.to_s => group.value }.to_json)
        return quantified_events unless group.parent

        quantified_events.where('properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(
          subscription,
          to_datetime + 1.day,
          current_usage: subscription.terminated? && subscription.upgraded?,
        ).charges_duration_in_days
      end

      # NOTE: when subscription is terminated or upgraded,
      #       we want to bill the persisted metrics at prorata of the full period duration.
      #       ie: the number of day of the terminated period divided by number of days without termination
      def persisted_pro_rata
        Utils::DatetimeService.date_diff_with_timezone(
          from_datetime,
          to_datetime,
          subscription.customer.applicable_timezone,
        ).fdiv(period_duration)
      end

      def persisted
        base_scope
          .where('quantified_events.added_at::timestamp(0) < ?', from_datetime)
          .where('quantified_events.removed_at IS NULL OR quantified_events.removed_at::timestamp(0) > ?', to_datetime)
      end

      def persisted_breakdown
        persisted_count = persisted.count
        return [] if persisted_count.zero?

        [
          OpenStruct.new(
            date: from_date_in_customer_timezone,
            action: 'add',
            count: persisted_count,
            duration: (to_date_in_customer_timezone + 1.day - from_date_in_customer_timezone).to_i,
            total_duration: period_duration,
          ),
        ]
      end

      def added
        base_scope
          .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
          .where('quantified_events.removed_at::timestamp(0) IS NULL OR quantified_events.removed_at > ?', to_datetime)
      end

      def added_breakdown
        date_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.added_at')

        added_list = added.group(Arel.sql("DATE(#{date_field})"))
          .order(Arel.sql("DATE(#{date_field}) ASC"))
          .pluck(Arel.sql(
            [
              "DATE(#{date_field}) as date",
              'COUNT(quantified_events.id) as metric_count',
            ].join(', '),
          ))

        added_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'add',
            count: aggregation.last,
            duration: (to_date_in_customer_timezone + 1.day - aggregation.first).to_i,
            total_duration: period_duration,
          )
        end
      end

      def removed
        base_scope
          .where('quantified_events.added_at::timestamp(0) < ?', from_datetime)
          .where('quantified_events.removed_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.removed_at::timestamp(0) <= ?', to_datetime)
      end

      def removed_breadown
        date_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.removed_at')

        removed_list = removed.group(Arel.sql("DATE(#{date_field})"))
          .order(Arel.sql("DATE(#{date_field}) ASC"))
          .pluck(Arel.sql(
            [
              "DATE(#{date_field}) as date",
              'COUNT(quantified_events.id) as metric_count',
            ].join(', '),
          ))

        removed_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'remove',
            count: aggregation.last,
            duration: (aggregation.first + 1.day - from_date_in_customer_timezone).to_i,
            total_duration: period_duration,
          )
        end
      end

      def added_and_removed
        base_scope
          .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
          .where('quantified_events.removed_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.removed_at::timestamp(0) <= ?', to_datetime)
      end

      def added_and_removed_breakdown
        added_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.added_at')
        removed_field = Utils::TimezoneService.date_in_customer_timezone_sql(customer, 'quantified_events.removed_at')

        added_and_removed_list = added_and_removed.group(
          Arel.sql("DATE(#{added_field}), DATE(#{removed_field})"),
        ).order(
          Arel.sql("DATE(#{added_field}) ASC, DATE(#{removed_field}) ASC"),
        ).pluck(Arel.sql(
          [
            "DATE(#{added_field}) as added_at",
            "DATE(#{removed_field}) as removed_at",
            'COUNT(quantified_events.id) as metric_count',
          ].join(', '),
        ))

        added_and_removed_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'add_and_removed',
            count: aggregation.last,
            duration: (aggregation.second.to_date + 1.day - aggregation.first.to_date).to_i,
            total_duration: period_duration,
          )
        end
      end

      # NOTE: Compute pro-rata of the duration in days between the datetimes over the duration of the billing period
      #       Dates are in customer timezone to make sure the duration is good
      def duration_ratio_sql(from, to)
        from_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, from)
        to_in_timezone = Utils::TimezoneService.date_in_customer_timezone_sql(customer, to)

        "SUM((DATE(#{to_in_timezone}) - DATE(#{from_in_timezone}) + 1)::numeric / #{period_duration})::numeric"
      end

      def sanitize_date(value)
        return ActiveRecord::Base.sanitize_sql_for_conditions(value) if value.is_a?(String)

        "'#{value}'"
      end
    end
  end
end
