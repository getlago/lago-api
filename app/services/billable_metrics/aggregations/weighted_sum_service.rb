# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def compute_aggregation(*)
        return empty_result if should_bypass_aggregation?

        weighted_result = event_store.weighted_sum(initial_value: period_initial_value)

        result.aggregation = weighted_result.value.ceil(20)
        result.count = weighted_result.events_count
        result.variation = weighted_result.variation
        result.total_aggregated_units = result.variation
        result.options = {}

        if presentation_by.present?
          initial_breakdowns = billable_metric.recurring? ? latest_breakdowns : []
          result.breakdowns = event_store.grouped_weighted_sum(
            uniq_grouped_by_and_presentation_by,
            initial_values: initial_breakdowns.map(&:with_indifferent_access)
          ).map(&:to_grouped_hash)
        end

        if billable_metric.recurring?
          result.total_aggregated_units = latest_value + result.variation
          result.recurring_units = result.total_aggregated_units
          result.recurring_updated_at = event_store.last_event&.timestamp || from_datetime
          result.breakdowns = latest_breakdowns if result.breakdowns.blank?
        end

        result
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      def compute_grouped_by_aggregation(*)
        return empty_results if should_bypass_aggregation?

        aggregations = event_store.grouped_weighted_sum(initial_values: grouped_latest_values)
        return empty_results if aggregations.blank?

        latest_values = []
        last_events = []
        if billable_metric.recurring?
          latest_values = grouped_latest_values
          last_events = event_store.grouped_last_event
        end

        if presentation_by.present?
          initial_breakdowns = billable_metric.recurring? ? grouped_latest_breakdowns : []
          result.breakdowns = event_store.grouped_weighted_sum(
            uniq_grouped_by_and_presentation_by,
            initial_values: initial_breakdowns.map(&:with_indifferent_access)
          ).map(&:to_grouped_hash)
          result.breakdowns = grouped_latest_breakdowns if result.breakdowns.empty?
        end

        result.aggregations = aggregations.map do |aggregation|
          group_result = BillableMetrics::Aggregations::BaseService::Result.new
          group_result.grouped_by = aggregation.groups

          group_result.aggregation = aggregation.value
          group_result.count = aggregation.events_count
          group_result.variation = aggregation.variation
          group_result.total_aggregated_units = group_result.variation

          if billable_metric.recurring?
            latest_value = latest_values.find { |c| c[:groups] == aggregation.groups }&.[](:value) || 0
            last_event = last_events.find { |c| c[:groups] == aggregation.groups }

            group_result.total_aggregated_units = latest_value + group_result.variation
            group_result.recurring_units = group_result.total_aggregated_units
            group_result.recurring_updated_at = last_event&.[](:timestamp) || from_datetime
          end

          group_result
        end

        result
      end

      private

      def period_initial_value
        return 0 unless billable_metric.recurring?

        latest_value
      end

      def latest_value
        return @latest_value if defined?(@latest_value)

        if latest_snapshots
          return @latest_value = latest_snapshots.first.units
        end

        if previous_events_counted?
          return @latest_value = latest_value_from_events.first
        end

        @latest_value = BigDecimal(0)
      end

      def latest_breakdowns
        return @latest_breakdowns if defined?(@latest_breakdowns)

        if latest_snapshots && !snapshot_breakdowns_missing?
          return @latest_breakdowns = latest_snapshots.first.presentation_breakdowns
        end

        if latest_snapshots || previous_events_counted?
          return @latest_breakdowns = latest_value_from_events.second
        end

        @latest_breakdowns = []
      end

      # A snapshot closing an older period misses the events of the periods in between.
      def latest_snapshots
        return @latest_snapshots if defined?(@latest_snapshots)

        @latest_snapshots = initial_value if initial_value.present? && initial_value.all? { it.to_datetime >= from_datetime - 1.second }
      end

      # Snapshots persisted before presentation breakdowns were stored hold none
      def snapshot_breakdowns_missing?
        presentation_by.present? && latest_snapshots.any? { it.presentation_breakdowns.empty? && !it.units.zero? }
      end

      # Without a snapshot, the units carried over are read from the events of the previous periods,
      # attached to the same external subscription ID (upgrades and downgrades included)
      def previous_events_counted?
        from_datetime > billing_context.started_at || billing_context.previous_subscription_id?
      end

      def latest_value_from_events
        return @latest_value_from_events if defined?(@latest_value_from_events)

        store = event_store.for_window(to_datetime: from_datetime - 1.second)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        @latest_value_from_events = [BigDecimal(store.sum(with_count: false).value), breakdowns]
      end

      def grouped_latest_values
        return @grouped_latest_values if defined?(@grouped_latest_values)

        if latest_snapshots
          return @grouped_latest_values = latest_snapshots.map { {groups: it.grouped_by, value: it.units} }
        end

        if previous_events_counted?
          return @grouped_latest_values = grouped_latest_values_from_events.first
        end

        @grouped_latest_values = {}
      end

      def grouped_latest_breakdowns
        return @grouped_latest_breakdowns if defined?(@grouped_latest_breakdowns)

        if latest_snapshots && !snapshot_breakdowns_missing?
          return @grouped_latest_breakdowns = latest_snapshots.flat_map(&:presentation_breakdowns)
        end

        if latest_snapshots || previous_events_counted?
          return @grouped_latest_breakdowns = grouped_latest_values_from_events.second
        end

        @grouped_latest_breakdowns = []
      end

      def grouped_latest_values_from_events
        return @grouped_latest_values_from_events if defined?(@grouped_latest_values_from_events)

        store = event_store.for_window(to_datetime: from_datetime - 1.second)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        @grouped_latest_values_from_events = [store.grouped_sum(with_count: false).map(&:to_grouped_hash), breakdowns]
      end
    end
  end
end
