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
      aggregator = aggregator_service.new(billable_metric:, subscription:, group:, event:)
      aggregator.aggregate(
        from_datetime: boundaries[:charges_from_datetime],
        to_datetime: boundaries[:charges_to_datetime],
        options: aggregation_options,
      )
    end

    private

    attr_reader :charge, :boundaries, :group, :properties, :event

    delegate :subscription, to: :event
    delegate :billable_metric, to: :charge

    def aggregator_service
      @aggregator_service ||= case billable_metric.aggregation_type.to_sym
                              when :count_agg
                                BillableMetrics::Aggregations::CountService
                              when :sum_agg
                                if charge.prorated?
                                  BillableMetrics::ProratedAggregations::SumService
                                else
                                  BillableMetrics::Aggregations::SumService
                                end
                              when :unique_count_agg
                                BillableMetrics::Aggregations::UniqueCountService
                              else
                                raise(NotImplementedError)
      end
    end

    def aggregation_options
      {
        free_units_per_events: properties['free_units_per_events'].to_i,
        free_units_per_total_aggregation: BigDecimal(properties['free_units_per_total_aggregation'] || 0),
      }
    end
  end
end
