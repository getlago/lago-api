# frozen_string_literal: true

module RecurringAggregationSnapshots
  # How the audits of subscription and contract snapshots read a fee's billed values and the events
  # ingested after a snapshot's watermark.
  module AuditComparison
    private

    # Per group, the units and events count of the store ingested after the watermark, up to `until_time`
    def ingested_after_watermark(store, watermark:, until_time:)
      until_fees = recurring_sums(store, until_time)
      until_watermark = recurring_sums(store, watermark)

      until_fees.to_h do |grouped_by, (units, events_count)|
        units_before, events_count_before = until_watermark.fetch(grouped_by, [0, 0])
        [grouped_by, [units - units_before, events_count - events_count_before]]
      end
    end

    def recurring_sums(store, watermark)
      results = if store.grouped_by.present?
        store.grouped_recurring_sum(watermark:)
      else
        [store.recurring_sum(watermark:)]
      end

      # Blank group values share the null group of the snapshot
      results.each_with_object({}) do |aggregation, sums|
        grouped_by = aggregation.respond_to?(:groups) ? aggregation.groups.compact.transform_values(&:to_s) : {}
        units, events_count = sums.fetch(grouped_by, [0, 0])
        sums[grouped_by] = [units + aggregation.snapshot_value, events_count + aggregation.snapshot_events_count]
      end
    end

    # A sum fee bills its units rounded and clamped at zero (see Fees::ChargeService#init_fee),
    # a weighted sum fee keeps them raw in total_aggregated_units
    def billed_units(billable_metric, units)
      if billable_metric.weighted_sum_agg?
        units
      else
        [BillableMetrics::Aggregations::ApplyRoundingService.call!(billable_metric:, units:).units, 0].max
      end
    end

    # Group values come back from JSON on both sides, the zero-unit marker with nil values
    def group_key(grouped_by)
      grouped_by.compact.transform_values(&:to_s)
    end
  end
end
