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

        weighted_result = event_store.weighted_sum(initial_value:)

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
        return empty_results if aggregations.blank?

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

      def initial_value
        return 0 unless billable_metric.recurring?

        latest_value
      end

      def latest_value
        return @latest_value if defined?(@latest_value)

        if latest_cached_aggregation
          return @latest_value = latest_cached_aggregation.current_aggregation
        end

        if billing_context.previous_subscription_id?
          return @latest_value = latest_value_from_events.first
        end

        @latest_value = BigDecimal(0)
      end

      def latest_breakdowns
        return @latest_breakdowns if defined?(@latest_breakdowns)

        if latest_cached_aggregation
          return @latest_breakdowns = latest_cached_aggregation.presentation_breakdowns
        end

        if billing_context.previous_subscription_id?
          return @latest_breakdowns = latest_value_from_events.second
        end

        @latest_breakdowns = []
      end

      def latest_cached_aggregation
        return @latest_cached_aggregation if defined?(@latest_cached_aggregation)

        @latest_cached_aggregation = latest_cached_aggregations
          .where(grouped_by: grouped_by.presence || {})
          .first
      end

      def latest_cached_aggregations
        return @latest_cached_aggregations if defined?(@latest_cached_aggregations)

        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: billing_context.external_id)
          .where(metered_item.cached_aggregation_identity)
          .where(timestamp: ...from_datetime)
          .order(timestamp: :desc, created_at: :desc)

        query = query.where(charge_filter_id: charge_filter.id) if charge_filter

        @latest_cached_aggregations = query
      end

      # NOTE: In case of upgrade/downgrade, if latest value is not persisted yet,
      #       we need to fetch latest value from previous events attached to the same external subscription ID
      def latest_value_from_events
        return @latest_value_from_events if defined?(@latest_value_from_events)

        store = event_store.for_window(to_datetime: previous_period_end)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        @latest_value_from_events = [BigDecimal(store.sum(with_count: false).value), breakdowns]
      end

      def grouped_latest_values
        return @grouped_latest_values if defined?(@grouped_latest_values)

        if grouped_latest_cached_aggregations.any?
          return @grouped_latest_values = grouped_latest_cached_aggregations.map do |cached_aggregation|
            {
              groups: cached_aggregation.grouped_by,
              value: cached_aggregation.current_aggregation
            }
          end
        end

        if billing_context.previous_subscription_id?
          return @grouped_latest_values = grouped_latest_values_from_events.first
        end

        @grouped_latest_values = {}
      end

      def grouped_latest_breakdowns
        return @grouped_latest_breakdowns if defined?(@grouped_latest_breakdowns)

        if grouped_latest_cached_aggregations.any?
          # Fees::ChargeService stores the breakdowns without the grouped_by keys of their group
          return @grouped_latest_breakdowns = grouped_latest_cached_aggregations.flat_map do |cached_aggregation|
            cached_aggregation.presentation_breakdowns.map do |breakdown|
              breakdown = breakdown.with_indifferent_access
              {groups: cached_aggregation.grouped_by.merge(breakdown[:groups]), value: breakdown[:value]}
            end
          end
        end

        if billing_context.previous_subscription_id?
          return @grouped_latest_breakdowns = grouped_latest_values_from_events.second
        end

        @grouped_latest_breakdowns = []
      end

      def grouped_latest_cached_aggregations
        return @grouped_latest_cached_aggregations if defined?(@grouped_latest_cached_aggregations)

        query = latest_cached_aggregations

        grouped_by.each do |key|
          query = query.where("grouped_by?:key", key:)
        end

        @grouped_latest_cached_aggregations = query.to_a.uniq(&:grouped_by)
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
        store = event_store.for_window(to_datetime: previous_period_end)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        [store.grouped_sum(with_count: false).map(&:to_grouped_hash), breakdowns]
      end
    end
  end
end
