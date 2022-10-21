# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class CountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        events = events_scope(from_date: from_date, to_date: to_date)

        result.aggregation = events.count
        result.aggregation_per_group = aggregation_per_group(events, aggregation_select)
        result
      end

      private

      def aggregation_select
        'count(id)'
      end
    end
  end
end
