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
        billing_context: Billing::Context.from(subscription:),
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

    def subscription
      metered_item.event.subscription
    end

    def aggregation_filters
      filters = {event: metered_item.event, charge_id: metered_item.charge_id}

      model = metered_item.charge_filter.presence || metered_item.charge
      grouped_by_values = model.pricing_group_keys&.index_with { metered_item.event.properties[it] } || {}
      if metered_item.charge.accepts_target_wallet && metered_item.event.properties["target_wallet_code"].present?
        grouped_by_values["target_wallet_code"] = metered_item.event.properties["target_wallet_code"]
      end
      filters[:grouped_by_values] = grouped_by_values if grouped_by_values.present?

      presentation_group_keys_values = metered_item.presentation_group_keys_values
      filters[:presentation_by] = presentation_group_keys_values if presentation_group_keys_values.present?

      if metered_item.charge_filter.present?
        matching_result = metered_item.matching_and_ignored_filters
        filters[:charge_filter] = metered_item.charge_filter if metered_item.charge_filter.persisted?
        filters[:matching_filters] = matching_result.matching_filters
        filters[:ignored_filters] = matching_result.ignored_filters
      end

      filters
    end
  end
end
