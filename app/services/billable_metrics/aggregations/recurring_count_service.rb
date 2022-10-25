# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class RecurringCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        @from_date = from_date
        @to_date = to_date

        result.aggregation = compute_aggregation.ceil(5)
        result.aggregation_per_group = aggregation_per_group
        result
      end

      def breakdown(from_date:, to_date:)
        @from_date = from_date.to_date
        @to_date = to_date.to_date

        breakdown = persisted_breakdown
        breakdown += added_breakdown
        breakdown += removed_breadown
        breakdown += added_and_removed_breakdown

        result.breakdown = breakdown.sort_by(&:date)
        result
      end

      private

      attr_reader :from_date, :to_date

      def compute_aggregation
        ActiveRecord::Base.connection.execute(aggregation_query).first['aggregation_result']
      end

      def aggregation_per_group
        return [] if groups.empty?

        ActiveRecord::Base.connection.execute(group_aggregation_query).map do |e|
          { e['group_name'] => e['total_sum'].ceil(5) } if e['group_name']
        end.compact
      end

      def sanitized_name(property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['persisted_events.properties->>?', property],
        )
      end

      def aggregation_query
        queries = [
          # NOTE: Billed on the full period
          persisted.select("SUM(#{persisted_pro_rata}::numeric)").to_sql,

          # NOTE: Added during the period
          added
            .select(
              "SUM(('#{to_date}'::date - DATE(persisted_events.added_at) + 1)::numeric / #{period_duration})::numeric",
            )
            .to_sql,

          # NOTE: removed during the period
          removed
            .select(
              "SUM((DATE(persisted_events.removed_at) - '#{from_date}'::date + 1)::numeric / #{period_duration})::numeric",
            )
            .to_sql,

          # NOTE: Added and then removed during the period
          added_and_removed
            .select(
              "SUM((DATE(persisted_events.removed_at) - DATE(persisted_events.added_at) + 1)::numeric / #{period_duration})::numeric",
            ).to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      def group_aggregation_query
        group_queries = groups.each_with_object([]) do |group, result|
          result << [
            # NOTE: Billed on the full period
            persisted.select(
              "(SUM(#{persisted_pro_rata}::numeric)) as group_sum, #{sanitized_name(group)} as group_name",
            ).group(sanitized_name(group)).to_sql,

            # NOTE: Added during the period
            added.select(
              "(SUM(('#{to_date}'::date - DATE(persisted_events.added_at) + 1)::numeric  / #{period_duration})::numeric) as group_sum, \
              #{sanitized_name(group)} as group_name",
            ).group(sanitized_name(group)).to_sql,

            # NOTE: removed during the period
            removed.select(
              "(SUM((DATE(persisted_events.removed_at) - '#{from_date}'::date + 1)::numeric / #{period_duration})::numeric) as group_sum, \
              #{sanitized_name(group)} as group_name",
            ).group(sanitized_name(group)).to_sql,

            # NOTE: Added and then removed during the period
            added_and_removed.select(
              "(SUM((DATE(persisted_events.removed_at) - DATE(persisted_events.added_at) + 1)::numeric / #{period_duration})::numeric) as group_sum, \
              #{sanitized_name(group)} as group_name",
            ).group(sanitized_name(group)).to_sql,
          ]
        end

        "SELECT SUM(COALESCE(group_sum, 0)) as total_sum, group_name \
        FROM (#{group_queries.join(' UNION ')}) AS global_query GROUP BY group_name"
      end

      def base_scope
        PersistedEvent
          .where(billable_metric_id: billable_metric.id)
          .where(customer_id: subscription.customer_id)
          .where(external_subscription_id: subscription.external_id)
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(subscription, to_date + 1.day)
          .charges_duration_in_days
      end

      # NOTE: when subscription is terminated or upgraded,
      #       we want to bill the persisted metrics at prorata of the full period duration.
      #       ie: the number of day of the terminated period divided by number of days without termination
      def persisted_pro_rata
        (to_date - from_date + 1).to_i.fdiv(period_duration)
      end

      def persisted
        base_scope
          .where('DATE(persisted_events.added_at) < ?', from_date)
          .where('persisted_events.removed_at IS NULL OR DATE(persisted_events.removed_at) > ?', to_date)
      end

      def persisted_breakdown
        persisted_count = persisted.count
        return [] if persisted_count.zero?

        [
          OpenStruct.new(
            date: from_date,
            action: 'add',
            count: persisted_count,
            duration: (to_date - from_date + 1).to_i,
            total_duration: period_duration,
          ),
        ]
      end

      def added
        base_scope
          .where('DATE(persisted_events.added_at) >= ?', from_date)
          .where('DATE(persisted_events.added_at) <= ?', to_date)
          .where('persisted_events.removed_at IS NULL OR DATE(persisted_events.removed_at) > ?', to_date)
      end

      def added_breakdown
        added_list = added.group('DATE(persisted_events.added_at)')
          .order('DATE(persisted_events.added_at) ASC')
          .pluck([
            'DATE(persisted_events.added_at) as date',
            'COUNT(persisted_events.id) as metric_count',
          ].join(', '))

        added_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'add',
            count: aggregation.last,
            duration: (to_date + 1.day - aggregation.first).to_i,
            total_duration: period_duration,
          )
        end
      end

      def removed
        base_scope
          .where('DATE(persisted_events.added_at) < ?', from_date)
          .where('DATE(persisted_events.removed_at) >= ?', from_date)
          .where('DATE(persisted_events.removed_at) <= ?', to_date)
      end

      def removed_breadown
        removed_list = removed.group('DATE(persisted_events.removed_at)')
          .order('DATE(persisted_events.removed_at) ASC')
          .pluck([
            'DATE(persisted_events.removed_at) as date',
            'COUNT(persisted_events.id) as metric_count',
          ].join(', '))

        removed_list.map do |aggregation|
          OpenStruct.new(
            date: aggregation.first.to_date,
            action: 'remove',
            count: aggregation.last,
            duration: (aggregation.first + 1.day - from_date).to_i,
            total_duration: period_duration,
          )
        end
      end

      def added_and_removed
        base_scope
          .where('DATE(persisted_events.added_at) >= ?', from_date)
          .where('DATE(persisted_events.added_at) <= ?', to_date)
          .where('DATE(persisted_events.removed_at) >= ?', from_date)
          .where('DATE(persisted_events.removed_at) <= ?', to_date)
      end

      def added_and_removed_breakdown
        added_and_removed_list = added_and_removed.group(
          'DATE(persisted_events.added_at), DATE(persisted_events.removed_at)',
        ).order('DATE(persisted_events.added_at) ASC, DATE(persisted_events.removed_at) ASC')
          .pluck([
            'DATE(persisted_events.added_at) as added_at',
            'DATE(persisted_events.removed_at) as removed_at',
            'COUNT(persisted_events.id) as metric_count',
          ].join(', '))

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
    end
  end
end
