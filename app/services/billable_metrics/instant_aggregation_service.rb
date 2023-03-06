# frozen_string_literal: true

module BillableMetrics
  class InstantAggregationService < BaseService
    def initialize(billable_metric:, boundaries:, properties:, event:, group: nil)
      @billable_metric = billable_metric
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

    attr_reader :billable_metric, :boundaries, :group, :properties, :event

    delegate :subscription, to: :event

    def aggregator_service
      @aggregator_service ||= case billable_metric.aggregation_type.to_sym
                              when :count_agg
                                BillableMetrics::Aggregations::CountService
                              when :sum_agg
                                BillableMetrics::Aggregations::SumService
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
