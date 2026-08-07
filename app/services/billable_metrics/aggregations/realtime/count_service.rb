# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    module Realtime
      # Serves count aggregation for current usage from the RisingWave-fed
      # usage_realtime_projections table instead of querying the events
      # store. Falls back to the parent (events-store) implementation when no
      # projection row is available.
      class CountService < BillableMetrics::Aggregations::CountService
        include ProjectionLookup

        def compute_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          row = projection_row
          return super if row.nil?

          result.aggregation = row.events_count
          result.current_usage_units = row.events_count
          result.count = row.events_count
          result.pay_in_advance_aggregation = BigDecimal(1)
          result.options = {running_total: running_total(options, aggregation: result.aggregation)}
          result
        end

        def compute_grouped_by_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          rows = grouped_projection_rows
          return super if rows.empty?

          result.aggregations = rows.map do |row, groups|
            group_result = BillableMetrics::Aggregations::BaseService::Result.new
            group_result.grouped_by = groups
            group_result.aggregation = row.events_count
            group_result.count = row.events_count
            group_result.current_usage_units = row.events_count
            group_result.options = {running_total: running_total(options, aggregation: group_result.aggregation)}
            group_result
          end

          result
        end
      end
    end
  end
end
