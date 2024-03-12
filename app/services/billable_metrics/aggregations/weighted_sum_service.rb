# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def compute_aggregation(*)
        result.aggregation = event_store.weighted_sum(initial_value:).ceil(20)
        result.count = event_store.count
        result.variation = event_store.sum || 0
        result.total_aggregated_units = result.variation
        result.options = {}

        if billable_metric.recurring?
          result.total_aggregated_units = latest_value + result.variation
          result.recurring_updated_at = event_store.last_event&.timestamp || from_datetime
        end

        result
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      def compute_grouped_by_aggregation(*)
        aggregations = event_store.grouped_weighted_sum(initial_values: grouped_latest_values)
        return empty_results if aggregations.blank?

        counts = event_store.grouped_count
        sums = event_store.grouped_sum

        latest_values = []
        last_events = []
        if billable_metric.recurring?
          latest_values = grouped_latest_values
          last_events = event_store.grouped_last_event
        end

        result.aggregations = aggregations.map do |aggregation|
          group_result = BaseService::Result.new
          group_result.grouped_by = aggregation[:groups]

          aggregation_value = aggregation[:value]
          group_result.aggregation = aggregation_value
          group_result.count = counts.find { |c| c[:groups] == aggregation[:groups] }&.[](:value) || 0
          group_result.variation = sums.find { |c| c[:groups] == aggregation[:groups] }&.[](:value) || 0
          group_result.total_aggregated_units = group_result.variation

          if billable_metric.recurring?
            latest_value = latest_values.find { |c| c[:groups] == aggregation[:groups] }&.[](:value) || 0
            last_event = last_events.find { |c| c[:groups] == aggregation[:groups] }

            group_result.total_aggregated_units = latest_value + group_result.variation
            group_result.recurring_updated_at = last_event&.[](:timestamp) || from_datetime
          end

          group_result
        end

        result
      end

      private

      def initial_value
        return 0 unless billable_metric.recurring?

        latest_value
      end

      def latest_value
        return @latest_value if @latest_value

        quantified_events = QuantifiedEvent
          .where(billable_metric_id: billable_metric.id)
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(added_at: ...from_datetime)
          .where(grouped_by: {})
          .order(added_at: :desc)

        quantified_events = quantified_events.where(group_id: group.id) if group
        quantified_event = quantified_events.first

        if quantified_event
          return @latest_value = BigDecimal(quantified_event.properties.[](QuantifiedEvent::RECURRING_TOTAL_UNITS))
        end
        return @latest_value = BigDecimal(latest_value_from_events) if subscription.previous_subscription_id?

        @latest_value = BigDecimal(0)
      end

      # NOTE: In case of upgrade/downgrade, if latest value is not persisted yet,
      #       we need to fetch latest value from previous events attached to the same external subscription ID
      def latest_value_from_events
        event_store = event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries: { to_datetime: from_datetime },
          filters:,
        )

        event_store.use_from_boundary = false
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        event_store.sum
      end

      def grouped_latest_values
        return @grouped_latest_values if @grouped_latest_values

        quantified_events = QuantifiedEvent
          .where(billable_metric_id: billable_metric.id)
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(added_at: ...from_datetime)
          .order(added_at: :desc)

        grouped_by.each do |key|
          quantified_events = quantified_events.where('grouped_by?:key', key:)
        end

        quantified_events = quantified_events.where(group_id: group.id) if group

        if quantified_events.all.any?
          return @grouped_latest_values = quantified_events.map do |quantified_event|
            {
              groups: quantified_event.grouped_by,
              value: BigDecimal(quantified_event.properties.[](QuantifiedEvent::RECURRING_TOTAL_UNITS)),
            }
          end
        end
        return @grouped_latest_values = grouped_latest_values_from_events if subscription.previous_subscription_id?

        @grouped_latest_values = {}
      end

      def grouped_latest_values_from_events
        event_store = event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries: { to_datetime: from_datetime },
          filters:,
        )

        event_store.use_from_boundary = false
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        event_store.grouped_sum
      end
    end
  end
end
