# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    module Realtime
      # Serves sum aggregation for current usage by summing the
      # RisingWave-fed 15-minute usage buckets (ClickHouse) instead of
      # querying the events store. Falls back to the parent (events-store)
      # implementation when no buckets cover the window.
      #
      # NOTE: sum's running_total with free units still hits the events store
      # (parent behavior); eligible charges are in arrears and non-recurring
      # (see RealtimeUsage.eligible_charge?), so window-scoped units are the
      # correct aggregation.
      class SumService < BillableMetrics::Aggregations::SumService
        include BucketLookup

        def compute_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          totals = bucket_totals
          return super if totals.nil?

          result.aggregation = totals.units
          result.pay_in_advance_aggregation = BigDecimal(0)
          result.count = totals.events_count
          result.options = {running_total: running_total(options)}
          result
        end

        def compute_grouped_by_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          rows = grouped_bucket_totals
          return super if rows.empty?

          result.aggregations = rows.map do |totals, groups|
            group_result = BillableMetrics::Aggregations::BaseService::Result.new
            group_result.grouped_by = groups
            group_result.aggregation = totals.units
            group_result.count = totals.events_count
            group_result.options = {running_total: running_total(options, grouped_by_values: group_result.grouped_by)}
            group_result
          end

          result
        end
      end
    end
  end
end
