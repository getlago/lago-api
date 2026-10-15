# frozen_string_literal: true

module Charges
  class PayInAdvanceAggregationService < BaseService
    Result = BaseResult

    def initialize(metered_item:, billing_context:)
      @metered_item = metered_item
      @billing_context = billing_context

      super
    end

    def call
      aggregator = BillableMetrics::AggregationFactory.new_instance(
        metered_item:,
        billing_context:,
        boundaries: {
          from_datetime: metered_item.boundaries.charges_from_datetime,
          to_datetime: metered_item.boundaries.charges_to_datetime,
          charges_duration: metered_item.boundaries.charges_duration,
          max_timestamp: metered_item.event.timestamp
        },
        filters: aggregation_filters,
        initial_value: recurring_initial_value
      )

      aggregation_result = aggregator.aggregate(options: aggregation_options)
      aggregation_result.pay_in_advance_count_delta ||= 1
      aggregation_result
    end

    private

    attr_reader :metered_item, :billing_context

    def aggregation_options
      {
        free_units_per_events: metered_item.properties["free_units_per_events"].to_i,
        free_units_per_total_aggregation: BigDecimal(metered_item.properties["free_units_per_total_aggregation"] || 0)
      }
    end

    def recurring_initial_value
      return unless snapshot_readable?

      snapshots = RecurringAggregationSnapshots::FetchService.call!(
        subscription: billing_context.subscription,
        charge: metered_item.charge,
        charge_filter: metered_item.charge_filter,
        grouped_by_keys: metered_item.pricing_group_keys,
        from_datetime: metered_item.boundaries.charges_from_datetime
      ).snapshots

      event_group_snapshots(snapshots) if snapshots
    end

    def snapshot_readable?
      return false unless metered_item.billable_metric.recurring? && metered_item.billable_metric.sum_agg?
      return false if metered_item.billing_segment
      return false unless billing_context.subscription?

      billing_context.organization.feature_flag_enabled?(:persisted_recurring_values)
    end

    # The aggregation only reads the group of the event. A group without a snapshot reads its
    # full history rather than assume it had no event before the period.
    def event_group_snapshots(snapshots)
      grouped_by = metered_item.grouped_by_values.transform_values { it&.to_s }
      snapshot = snapshots.find { it.grouped_by.transform_values { |value| value&.to_s } == grouped_by }

      [snapshot] if snapshot
    end

    def aggregation_filters
      # BaseStore reads charge_id; ClickhouseEnrichedStore uses it to select pre-enriched events.
      # Raw Postgres/ClickHouse aggregation uses metric code, billing context, and property filters instead.
      #
      # TODO: Support product_id in BaseStore and the enriched-event schema, enrichment, queries, and dedup keys.
      # Adding a product_id key here alone would be ignored. StoreFactory also needs a product-compatible path.
      filters = {event: metered_item.event, charge_id: metered_item.charge_id}

      grouped_by_values = metered_item.grouped_by_values
      filters[:grouped_by_values] = grouped_by_values if grouped_by_values.present?

      presentation_group_keys_values = metered_item.presentation_group_keys_values
      filters[:presentation_by] = presentation_group_keys_values if presentation_group_keys_values.present?

      if metered_item.billing_segment || metered_item.charge_filter.present?
        matching_result = metered_item.matching_and_ignored_filters
        # Aggregations::BaseService retains this object for charge_filter_id cache lookups;
        # WeightedSumService and CustomService also scope cached state by it. CustomService reads
        # its custom_properties, while BaseStore extracts its ID for enriched-event queries.
        filters[:charge_filter] = metered_item.charge_filter if metered_item.charge_filter&.persisted?
        filters[:matching_filters] = matching_result.matching_filters
        filters[:ignored_filters] = matching_result.ignored_filters
      end

      filters
    end
  end
end
