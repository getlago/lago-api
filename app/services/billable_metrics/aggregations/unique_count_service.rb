# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_date:, to_date:, options: {})
        events = events_scope(from_date: from_date, to_date: to_date)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.count("DISTINCT (#{sanitized_field_name})")
        result.count = events.count
        result.options = {}
        result
      end
    end
  end
end
