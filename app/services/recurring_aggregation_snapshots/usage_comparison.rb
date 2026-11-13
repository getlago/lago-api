# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Leaves shared by the current usage comparisons: a leaf is an item (a subscription's charge or a
  # contract's product), its filter and a group. The host defines snapshot_keys, the (item, filter)
  # pairs read from a snapshot, and billable_metric_code(item_id).
  module UsageComparison
    Totals = Data.define(:units, :total_aggregated_units, :amount_cents, :events_count, :presentation_breakdowns)
    EMPTY_TOTALS = Totals.new(
      units: BigDecimal(0), total_aggregated_units: BigDecimal(0), amount_cents: 0, events_count: 0, presentation_breakdowns: {}
    )

    Row = Data.define(:item_id, :billable_metric_code, :filter_id, :grouped_by, :snapshot_read, :snapshot, :full_scan) do
      # Without a snapshot both runs scan the full history: a difference there is an event ingested
      # between them, never a snapshot bug.
      def different?
        snapshot_read && snapshot != full_scan
      end
    end

    private

    # Leaves: one [item_id, filter_id, fee] per fee of each run
    def build_rows(snapshot_leaves:, full_scan_leaves:)
      snapshot_totals = totals_by_key(snapshot_leaves)
      full_scan_totals = totals_by_key(full_scan_leaves)

      (snapshot_totals.keys | full_scan_totals.keys).map do |key|
        item_id, filter_id, grouped_by = key

        Row.new(
          item_id:,
          billable_metric_code: billable_metric_code(item_id),
          filter_id:,
          grouped_by:,
          snapshot_read: snapshot_keys.include?([item_id, filter_id]),
          snapshot: snapshot_totals[key] || EMPTY_TOTALS,
          full_scan: full_scan_totals[key] || EMPTY_TOTALS
        )
      end
    end

    def totals_by_key(leaves)
      leaves.each_with_object({}) do |(item_id, filter_id, fee), totals|
        key = [item_id, filter_id, normalized_values(fee.grouped_by)]
        current = totals[key] || EMPTY_TOTALS
        totals[key] = Totals.new(
          units: current.units + fee.units.to_d,
          total_aggregated_units: current.total_aggregated_units + fee.total_aggregated_units.to_d,
          amount_cents: current.amount_cents + fee.amount_cents.to_i,
          events_count: current.events_count + fee.events_count.to_i,
          presentation_breakdowns: add_breakdowns(current.presentation_breakdowns, fee)
        )
      end
    end

    # Zero lines are skipped: a group closing a period at zero keeps no snapshot row, so the snapshot
    # run drops the zero lines the full scan carries from the cached aggregation.
    def add_breakdowns(breakdowns, fee)
      fee.presentation_breakdowns.each_with_object(breakdowns.dup) do |breakdown, sums|
        next if breakdown.units.to_d.zero?

        presentation_by = normalized_values(breakdown.presentation_by)
        sums[presentation_by] = sums.fetch(presentation_by, BigDecimal(0)) + breakdown.units.to_d
      end
    end

    # The snapshot path reads group values back from JSON, the full scan from the events.
    def normalized_values(values)
      (values || {}).transform_values { it&.to_s }
    end

    # BillableMetrics::Aggregations::WeightedSumService#latest_snapshots, SumService#delta_period:
    # a weighted sum only starts from a period closing right before its own.
    def starts_from_period?(billable_metric, period, from_datetime)
      !billable_metric.weighted_sum_agg? || period.to_datetime.between?(from_datetime - 1.second, from_datetime)
    end
  end
end
