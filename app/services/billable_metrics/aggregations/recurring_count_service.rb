# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class RecurringCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        @from_date = from_date
        @to_date = to_date

        result.aggregation = compute_aggregation.ceil(5)
        result.count = result.aggregation
        result.options = {}
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

      def base_scope
        persisted_events = PersistedEvent
          .where(billable_metric_id: billable_metric.id)
          .where(customer_id: subscription.customer_id)
          .where(external_subscription_id: subscription.external_id)

        return persisted_events unless group

        persisted_events = persisted_events.where('properties @> ?', { group.key.to_s => group.value }.to_json)
        return persisted_events unless group.parent

        persisted_events.where('properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        # TODO: pass a datetime argument
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
