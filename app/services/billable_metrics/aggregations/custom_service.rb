# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CustomService < BillableMetrics::Aggregations::BaseService
      class CustomEvent
        def initialize(properties, timestamp)
          @properties = properties
          @timestamp = timestamp
        end

        attr_reader :properties, :timestamp
      end

      def compute_aggregation(options: {})
        result.aggregation = 0 # NOTE: aggregation will be computed via a custom aggregation in the charge model
        result.count = event_store.count
        result.options = options
        result
      end

      def compute_per_event_aggregation
        event_store.events_properties.map do |res|
          CustomEvent.new(res.first, res.last)
        end
      end
    end
  end
end
