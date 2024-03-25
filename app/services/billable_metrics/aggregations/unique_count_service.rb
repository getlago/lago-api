# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.aggregation_property = billable_metric.field_name
        event_store.use_from_boundary = !billable_metric.recurring
      end

      def compute_aggregation(options: {})
        aggregation = event_store.unique_count.ceil(5)

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
        aggregations = event_store.grouped_unique_count
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

        active_unique_property = event_store.active_unique_property?(event)

        newly_applied_units = if operation_type == :add
          # NOTE: ensure the unique property is not already present
          active_unique_property ? 0 : 1
        else
          0
        end

        cached_aggregation = find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: grouped_by_values,
        )

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

        current_aggregation = if operation_type == :add
          old_aggregation + newly_applied_units
        else
          # NOTE: ensure the unique property is active
          old_aggregation - (active_unique_property ? 1 : 0)
        end

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
        (0...event_store.events_values(force_from: true).count).map { |_| 1 }
      end

      # This method fetches the latest cached aggregation in current period. If such a record exists we know that
      # previous aggregation and previous maximum aggregation are stored there. Fetching these values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def find_cached_aggregation(with_from_datetime:, with_to_datetime:, grouped_by: nil)
        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(charge_id: charge.id)
          .from_datetime(with_from_datetime)
          .to_datetime(with_to_datetime)
          .where(grouped_by: grouped_by.presence || {})
          .order(timestamp: :desc, created_at: :desc)

        query = query.where.not(event_id: event.id) if event.present?
        query = query.where(group_id: group.id) if group
        query = query.where(charge_filter_id: charge_filter.id) if charge_filter

        query.first
      end

      def count_unique_group_scope(events)
        events = events.where('quantified_events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return events unless group.parent

        events.where('quantified_events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      protected

      def operation_type
        @operation_type ||= event.properties.fetch('operation_type', 'add')&.to_sym
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil, units_applied: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
      end
    end
  end
end
