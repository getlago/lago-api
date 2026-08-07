# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    module Realtime
      # Serves sum aggregation for current usage from the RisingWave-fed
      # usage_realtime_projections table instead of querying the events
      # store. Falls back to the parent (events-store) implementation when no
      # projection rows are available.
      #
      # NOTE: sum's running_total with free units still hits the events store
      # (parent behavior); eligible charges are in arrears and non-recurring
      # (see UsageProjections.eligible_charge?), so period-scoped units are
      # the correct aggregation.
      class SumService < BillableMetrics::Aggregations::SumService
        include ProjectionLookup

        def compute_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          row = projection_row
          return super if row.nil?

          result.aggregation = row.units
          result.pay_in_advance_aggregation = BigDecimal(0)
          result.count = row.events_count
          result.options = {running_total: running_total(options)}
          result
        end

        def compute_grouped_by_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          rows = grouped_projection_rows
          return super if rows.empty?

          result.aggregations = rows.map do |row, groups|
            group_result = BillableMetrics::Aggregations::BaseService::Result.new
            group_result.grouped_by = groups
            group_result.aggregation = row.units
            group_result.count = row.events_count
            group_result.options = {running_total: running_total(options, grouped_by_values: group_result.grouped_by)}
            group_result
          end

          result
        end
      end
    end
  end
end
