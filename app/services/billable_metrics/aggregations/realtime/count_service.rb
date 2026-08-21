# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    module Realtime
      # Serves count aggregation for current usage by summing the
      # RisingWave-fed 15-minute usage buckets (ClickHouse) instead of
      # querying the events store. Falls back to the parent (events-store)
      # implementation when no buckets cover the window.
      class CountService < BillableMetrics::Aggregations::CountService
        include BucketLookup

        def compute_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          totals = bucket_totals
          return super if totals.nil?

          result.aggregation = totals.events_count
          result.current_usage_units = totals.events_count
          result.count = totals.events_count
          result.pay_in_advance_aggregation = BigDecimal(1)
          result.options = {running_total: running_total(options, aggregation: result.aggregation)}
          result
        end

        def compute_grouped_by_aggregation(options: {})
          return super if should_bypass_aggregation? || presentation_by.present?

          rows = grouped_bucket_totals
          return super if rows.empty?

          result.aggregations = rows.map do |totals, groups|
            group_result = BillableMetrics::Aggregations::BaseService::Result.new
            group_result.grouped_by = groups
            group_result.aggregation = totals.events_count
            group_result.count = totals.events_count
            group_result.current_usage_units = totals.events_count
            group_result.options = {running_total: running_total(options, aggregation: group_result.aggregation)}
            group_result
          end

          result
        end
      end
    end
  end
end
