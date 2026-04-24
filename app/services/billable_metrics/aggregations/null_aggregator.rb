# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    # Null object used when a null aggregation result is constructed outside of a real aggregator
    # (e.g. when rebuilding zero fees in Fees::ChargeService#hydrate_non_persistable_fees).
    # Provides a safe empty response for per_event_aggregation so charge models that call into the
    # aggregator do not crash.
    class NullAggregator
      def per_event_aggregation(exclude_event: false, include_event_value: false, grouped_by_values: nil)
        BaseService::PerEventAggregationResult.new.tap do |result|
          result.event_aggregation = []
        end
      end
    end
  end
end
