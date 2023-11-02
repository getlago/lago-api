# frozen_string_literal: true

module Charges
  class PayInAdvanceAggregationService < BaseService
    def initialize(charge:, boundaries:, properties:, event:, group: nil)
      @charge = charge
      @boundaries = boundaries
      @properties = properties
      @event = event
      @group = group

      super
    end

    def call
      aggregator = BillableMetrics::AggregationFactory.new_instance(
        charge:,
        subscription:,
        group:,
        event:,
        boundaries: {
          from_datetime: boundaries[:charges_from_datetime],
          to_datetime: boundaries[:charges_to_datetime],
        },
      )

      aggregator.aggregate(options: aggregation_options)
    end

    private

    attr_reader :charge, :boundaries, :group, :properties, :event

    delegate :subscription, to: :event
    delegate :billable_metric, to: :charge

    def aggregation_options
      {
        free_units_per_events: properties['free_units_per_events'].to_i,
        free_units_per_total_aggregation: BigDecimal(properties['free_units_per_total_aggregation'] || 0),
      }
    end
  end
end
