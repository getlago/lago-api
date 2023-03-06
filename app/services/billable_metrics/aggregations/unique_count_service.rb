# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_datetime:, to_datetime:, options: {})
        events = events_scope(from_datetime:, to_datetime:)
          .where("#{sanitized_field_name} IS NOT NULL")

        result.aggregation = events.count("DISTINCT (#{sanitized_field_name})")
        result.instant_aggregation = BigDecimal(compute_instant_aggregation(events))
        result.count = events.count
        result.options = options
        result
      end

      def compute_instant_aggregation(events)
        return 0 unless event
        return 0 if event.properties.blank?

        existing_property = events
          .where("#{sanitized_field_name} = '#{event.properties[billable_metric.field_name]}'")
          .where.not(id: event.id)
          .any?

        # NOTE: bill only property that have not been received in the period yet
        return 0 if existing_property

        1
      end
    end
  end
end
