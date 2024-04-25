# frozen_string_literal: true

module Charges
  class PayInAdvanceAggregationService < BaseService
    def initialize(charge:, boundaries:, properties:, event:, charge_filter: nil)
      @charge = charge
      @boundaries = boundaries
      @properties = properties
      @event = event
      @charge_filter = charge_filter

      super
    end

    def call
      aggregator = BillableMetrics::AggregationFactory.new_instance(
        charge:,
        subscription:,
        boundaries: {
          from_datetime: boundaries[:charges_from_datetime],
          to_datetime: boundaries[:charges_to_datetime],
          charges_duration: boundaries[:charges_duration],
        },
        filters: aggregation_filters,
      )

      aggregator.aggregate(options: aggregation_options)
    end

    private

    attr_reader :charge, :boundaries, :properties, :event, :charge_filter

    delegate :subscription, to: :event
    delegate :billable_metric, to: :charge

    def aggregation_options
      {
        free_units_per_events: properties['free_units_per_events'].to_i,
        free_units_per_total_aggregation: BigDecimal(properties['free_units_per_total_aggregation'] || 0),
      }
    end

    def aggregation_filters
      filters = { event: }

      properties = charge_filter&.properties || charge.properties
      if charge.standard? && properties['grouped_by'].present?
        filters[:grouped_by_values] = properties['grouped_by'].index_with do |grouped_by|
          event.properties[grouped_by]
        end
      end

      if charge_filter.present?
        result = ChargeFilters::MatchingAndIgnoredService.call(filter: charge_filter)
        filters[:charge_filter] = charge_filter if charge_filter.persisted?
        filters[:matching_filters] = result.matching_filters
        filters[:ignored_filters] = result.ignored_filters
      end

      filters
    end
  end
end
