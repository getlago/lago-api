# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def aggregate(*)
        result.aggregation = event_store.weighted_sum(initial_value:).ceil(20)
        result.count = event_store.count
        result.variation = event_store.sum || 0
        result.total_aggregated_units = result.variation

        if billable_metric.recurring?
          result.total_aggregated_units = latest_value + result.variation
          result.recurring_updated_at = event_store.last_event&.timestamp || from_datetime
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
          group:,
          event:,
        )

        event_store.use_from_boundary = false
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        event_store.sum
      end
    end
  end
end
