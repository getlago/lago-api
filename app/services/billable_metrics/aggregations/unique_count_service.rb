# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.aggregation_property = billable_metric.field_name
      end

      def compute_aggregation(options: {})
        aggregation = compute_single_aggregation.ceil(5)

        if options[:is_pay_in_advance] && options[:is_current_usage]
          handle_in_advance_current_usage(aggregation)
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = BigDecimal(compute_pay_in_advance_aggregation)
        result.options = { running_total: running_total(options) }
        result.count = result.aggregation
        result
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      #
      #       This logic is only applicable for in arrears aggregation
      #       (exept for the current_usage update)
      #       as pay in advance aggregation will be computed on a single group
      #       with the grouped_by_values filter
      def compute_grouped_by_aggregation(options: {})
        aggregations = compute_grouped_aggregations
        return empty_results if aggregations.blank?

        result.aggregations = aggregations.map do |aggregation|
          group_result = BaseService::Result.new
          group_result.grouped_by = aggregation[:groups]

          if options[:is_pay_in_advance] && options[:is_current_usage]
            handle_in_advance_current_usage(aggregation[:value], target_result: group_result)
          else
            group_result.aggregation = aggregation[:value]
          end

          group_result.count = aggregation[:value]
          group_result
        end

        result
      end

      def compute_pay_in_advance_aggregation
        return 0 unless event
        return 0 if event.properties.blank?

        newly_applied_units = (operation_type == :add) ? 1 : 0

        cached_aggregation = find_cached_aggregation

        unless cached_aggregation
          handle_event_metadata(
            current_aggregation: newly_applied_units,
            max_aggregation: newly_applied_units,
            units_applied: newly_applied_units,
          )

          return newly_applied_units
        end

        old_aggregation = BigDecimal(cached_aggregation.current_aggregation)
        old_max = BigDecimal(cached_aggregation.max_aggregation)

        current_aggregation = (operation_type == :add) ? (old_aggregation + 1) : (old_aggregation - 1)

        if current_aggregation > old_max
          handle_event_metadata(current_aggregation:, max_aggregation: current_aggregation)

          1
        else
          handle_event_metadata(current_aggregation:, max_aggregation: old_max, units_applied: newly_applied_units)

          0
        end
      end

      # NOTE: Return cumulative sum of event count based on the number of free units
      #       (per_events or per_total_aggregation).
      def running_total(options)
        free_units_per_events = options[:free_units_per_events].to_i
        free_units_per_total_aggregation = BigDecimal(options[:free_units_per_total_aggregation] || 0)

        return [] if free_units_per_events.zero? && free_units_per_total_aggregation.zero?

        (1..result.aggregation).to_a
      end

      def compute_per_event_aggregation
        (0...added_query.count).map { |_| 1 }
      end

      # This method fetches the latest cached aggregation in current period. If such a record exists we know that
      # previous aggregation and previous maximum aggregation are stored there. Fetching these values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def find_cached_aggregation(with_from_datetime: from_datetime, with_to_datetime: to_datetime, grouped_by: nil)
        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(charge_id: charge.id)
          .from_datetime(with_from_datetime)
          .to_datetime(with_to_datetime)
          .order(timestamp: :desc)

        query = query
          .joins(:charge)
          .joins([
            'INNER JOIN quantified_events ON quantified_events.organization_id = cached_aggregations.organization_id',
            'quantified_events.external_subscription_id = cached_aggregations.external_subscription_id',
            'quantified_events.billable_metric_id = charges.billable_metric_id',
            'quantified_events.grouped_by = cached_aggregations.grouped_by',
          ].join(' AND '))
          .where(quantified_events: { external_id: event_store.events_values })
          .where('quantified_events.added_at::timestamp(0) >= ?', with_from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', with_to_datetime)
          .where('quantified_events.removed_at::timestamp(0) IS NULL')
          .or(
            query
              .where('quantified_events.removed_at::timestamp(0) >= ?', with_from_datetime)
              .where('quantified_events.removed_at::timestamp(0) <= ?', with_to_datetime),
          )
          .where(grouped_by: grouped_by.presence || {})

        # TODO: event_id for clickhouse events
        query = query.where.not(event_id: event.id) if event.present?

        if group
          query = query.where(group_id: group.id)
            .where('quantified_events.group_id = cached_aggregations.group_id')
        end

        @cached_aggregation = query.first
      end

      def count_unique_group_scope(events)
        events = events.where('quantified_events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return events unless group.parent

        events.where('quantified_events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      protected

      def support_grouped_aggregation?
        true
      end

      def operation_type
        @operation_type ||= event.properties.fetch('operation_type', 'add')&.to_sym
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil, units_applied: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
      end

      def compute_single_aggregation
        ActiveRecord::Base.connection.execute(aggregation_query).first['aggregation_result']
      end

      def compute_grouped_aggregations
        event_store.prepare_grouped_result(
          ActiveRecord::Base.connection.select_all(grouped_aggregation_query).rows,
        )
      end

      def aggregation_query
        queries = [
          # NOTE: Billed on the full period. We will replace 1::numeric with proration_coefficient::numeric
          # in the next part
          persisted_query.select('SUM(1::numeric)').to_sql,

          # NOTE: Added during the period, We will replace 1::numeric with proration_coefficient::numeric
          # in the next part
          added_query.select('SUM(1::numeric)').to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      def grouped_aggregation_query
        groups = grouped_by.map do |group|
          ActiveRecord::Base.sanitize_sql_for_conditions(
            ['quantified_events.grouped_by->>?', group],
          )
        end
        group_names = groups.map.with_index { |_, index| "g_#{index}" }.join(', ')

        # NOTE: Billed on the full period
        persisted = persisted_query
          .select(
            [
              groups.map.with_index { |group, index| "#{group} AS g_#{index}" },
              '1::numeric AS group_sum',
            ].flatten.join(', '),
          )
          .group(groups.join(', '))
          .to_sql

        # NOTE: Added during the period
        added = added_query
          .select(
            [
              groups.map.with_index { |group, index| "#{group} AS g_#{index}" },
              '1::numeric AS group_sum',
            ].flatten.join(', '),
          )
          .group(groups.join(', '))
          .to_sql

        <<-SQL
          with persisted AS (#{persisted}),
          added AS (#{added})

          SELECT
            #{group_names},
            SUM(group_sum)
          FROM (
            (select * from persisted)
          UNION ALL
            (select * from added)
          ) grouped_count
          GROUP BY #{group_names}
        SQL
      end

      def persisted_query
        return QuantifiedEvent.none unless billable_metric.recurring?

        base_scope
          .where('quantified_events.added_at::timestamp(0) < ?', from_datetime)
          .where('quantified_events.removed_at IS NULL OR quantified_events.removed_at::timestamp(0) > ?', to_datetime)
      end

      def added_query
        base_scope
          .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
          .where('quantified_events.removed_at::timestamp(0) IS NULL OR quantified_events.removed_at > ?', to_datetime)
      end

      def base_scope
        quantified_events = QuantifiedEvent
          .where(organization_id: billable_metric.organization_id)
          .where(billable_metric_id: billable_metric.id)
          .where(external_subscription_id: subscription.external_id)

        unless billable_metric.recurring?
          store = event_store_class.new(
            code: billable_metric.code,
            subscription:,
            boundaries: {
              from_datetime: subscription.started_at,
              to_datetime: subscription.terminated_at,
            },
            filters:,
          )
          store.aggregation_property = billable_metric.field_name

          quantified_events = quantified_events.where(external_id: store.events_values)
        end

        return quantified_events unless group

        count_unique_group_scope(quantified_events)
      end

      def sanitized_operation_type
        ActiveRecord::Base.sanitize_sql_for_conditions(['events.properties->>operation_type'])
      end
    end
  end
end
