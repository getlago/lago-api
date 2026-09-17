# frozen_string_literal: true

module Charges
  class PayInAdvanceAggregationService < BaseService
    Result = BaseResult

    def initialize(metered_item:)
      @metered_item = metered_item

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
        filters: aggregation_filters
      )

      aggregator.aggregate(options: aggregation_options)
    end

    private

    attr_reader :metered_item

    def aggregation_options
      {
        free_units_per_events: metered_item.properties["free_units_per_events"].to_i,
        free_units_per_total_aggregation: BigDecimal(metered_item.properties["free_units_per_total_aggregation"] || 0)
      }
    end

    def aggregation_filters
      # BaseStore reads charge_id; ClickhouseEnrichedStore uses it to select pre-enriched events.
      # Raw Postgres/ClickHouse aggregation uses metric code, billing context, and property filters instead.
      #
      # TODO: Support product_id in BaseStore and the enriched-event schema, enrichment, queries, and dedup keys.
      # Adding a product_id key here alone would be ignored. StoreFactory also needs a product-compatible path.
      # CachedAggregation reads in Aggregations::{BaseService, WeightedSumService, CustomService} obtain
      # charge_id from MeteredItem directly; those lookups and the cache schema also need product identity.
      filters = {event: metered_item.event, charge_id: metered_item.charge_id}

      grouped_by_values = metered_item.grouped_by_values
      filters[:grouped_by_values] = grouped_by_values if grouped_by_values.present?

      presentation_group_keys_values = metered_item.presentation_group_keys_values
      filters[:presentation_by] = presentation_group_keys_values if presentation_group_keys_values.present?

      if metered_item.charge_filter.present?
        matching_result = metered_item.matching_and_ignored_filters
        # Aggregations::BaseService retains this object for charge_filter_id cache lookups;
        # WeightedSumService and CustomService also scope cached state by it. CustomService reads
        # its custom_properties, while BaseStore extracts its ID for enriched-event queries.
        #
        # TODO: Carry product_filter/selected_filter through aggregators, stores, enrichment, and cache
        # schemas/keys, preserving nil as the default bucket. Keep product custom_properties on the
        # segment's pricing snapshot; product event matching already uses matching/ignored_filters below.
        filters[:charge_filter] = metered_item.charge_filter if metered_item.charge_filter.persisted?
        filters[:matching_filters] = matching_result.matching_filters
        filters[:ignored_filters] = matching_result.ignored_filters
      end

      filters
    end

    def billing_context
      return @billing_context if defined?(@billing_context)

      @billing_context = if metered_item.billing_segment
        Billing::Context.from(contract: metered_item.contract)
      else
        Billing::Context.from(subscription: metered_item.event.subscription)
      end
    end
  end
end
