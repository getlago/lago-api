# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        events = events_scope(from_date: from_date, to_date: to_date)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.count("DISTINCT (#{sanitized_field_name})")
        result.aggregation_per_group = aggregation_per_group(events, aggregation_select)
        result.count = events.count
        result
      end

      private

      def aggregation_select
        "count(distinct(#{sanitized_field_name}))"
      end
    end
  end
end
