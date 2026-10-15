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

        compute_breakdowns(billable_metric.recurring? ? latest_breakdowns : []) if presentation_by.present?

        if billable_metric.recurring?
          result.total_aggregated_units = latest_value + result.variation
          result.recurring_units = result.total_aggregated_units
          result.recurring_updated_at = event_store.last_event&.timestamp || from_datetime
          if result.breakdowns.blank?
            result.breakdowns = latest_breakdowns
            result.recurring_breakdowns = latest_breakdowns
          end
        end

        result
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      def compute_grouped_by_aggregation(*)
        return empty_results if should_bypass_aggregation?

        aggregations = event_store.grouped_weighted_sum(initial_values: grouped_latest_values)
        if aggregations.blank?
          empty_results
          # No group carried over or in the period: the bucket closes at zero units
          result.aggregations.each { it.recurring_units = 0 } if billable_metric.recurring?
          return result
        end

        latest_values = []
        last_events = []
        if billable_metric.recurring?
          latest_values = grouped_latest_values
          last_events = event_store.grouped_last_event
        end

        if presentation_by.present?
          compute_breakdowns(billable_metric.recurring? ? grouped_latest_breakdowns : [])
          if result.breakdowns.empty?
            result.breakdowns = grouped_latest_breakdowns
            result.recurring_breakdowns = grouped_latest_breakdowns if billable_metric.recurring?
          end
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

      def compute_breakdowns(previous_breakdowns)
        initial_values = previous_breakdowns.map(&:with_indifferent_access)
        grouped_results = event_store.grouped_weighted_sum(uniq_grouped_by_and_presentation_by, initial_values:)

        result.breakdowns = grouped_results.map(&:to_grouped_hash)
        return unless billable_metric.recurring?

        # The fee shows the weighted units, the next period starts from the units active at period end
        result.recurring_breakdowns = grouped_results.map do |grouped_result|
          initial_value = initial_values.find { it[:groups] == grouped_result.groups }&.[](:value)
          {groups: grouped_result.groups, value: (initial_value || 0).to_d + grouped_result.variation}
        end
      end

      def period_initial_value
        return 0 unless billable_metric.recurring?

        latest_value
      end

      def latest_value
        return @latest_value if defined?(@latest_value)

        if latest_snapshots
          return @latest_value = latest_snapshots.sum(BigDecimal(0), &:units)
        end

        if previous_events_counted?
          return @latest_value = latest_value_from_events.first
        end

        @latest_value = BigDecimal(0)
      end

      def latest_breakdowns
        return @latest_breakdowns if defined?(@latest_breakdowns)

        if latest_snapshots
          return @latest_breakdowns = latest_snapshots.flat_map(&:presentation_breakdowns)
        end

        if previous_events_counted?
          return @latest_breakdowns = latest_value_from_events.second
        end

        @latest_breakdowns = []
      end

      # A snapshot closing an older period misses the events of the periods in between.
      # Without snapshots, the period still tells that the bucket had no active units.
      def latest_snapshots
        return @latest_snapshots if defined?(@latest_snapshots)

        @latest_snapshots = initial_value if initial_period && initial_period.to_datetime >= from_datetime - 1.second
      end

      # Without a snapshot, the units carried over are read from the events of the previous periods,
      # attached to the same external subscription ID (upgrades and downgrades included)
      def previous_events_counted?
        from_datetime > billing_context.started_at || billing_context.previous_subscription_id?
      end

      def latest_value_from_events
        return @latest_value_from_events if defined?(@latest_value_from_events)

        store = event_store.for_window(to_datetime: previous_period_end)
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

        if latest_snapshots
          return @grouped_latest_breakdowns = latest_snapshots.flat_map do
            with_grouped_by_keys(it.grouped_by, it.presentation_breakdowns)
          end
        end

        if previous_events_counted?
          return @grouped_latest_breakdowns = grouped_latest_values_from_events.second
        end

        @grouped_latest_breakdowns = []
      end

      # Fees::ChargeService stores the breakdowns without the grouped_by keys of their group
      def with_grouped_by_keys(grouped_by, breakdowns)
        breakdowns.map do |breakdown|
          breakdown = breakdown.with_indifferent_access
          {groups: grouped_by.merge(breakdown[:groups]), value: breakdown[:value]}
        end
      end

      def previous_period_end
        precision = if event_store.is_a?(Events::Stores::ClickhouseStore)
          0.001.seconds
        else
          0.000001.seconds
        end

        from_datetime - precision
      end

      def grouped_latest_values_from_events
        return @grouped_latest_values_from_events if defined?(@grouped_latest_values_from_events)

        store = event_store.for_window(to_datetime: previous_period_end)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        @grouped_latest_values_from_events = [store.grouped_sum(with_count: false).map(&:to_grouped_hash), breakdowns]
      end
    end
  end
end
