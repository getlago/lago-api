# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Computes the current usage of one subscription twice, once starting the recurring charges from
  # their snapshots and once scanning their full history, and compares them per
  # (charge, charge filter, group). Both runs share one timestamp and skip the charge caches, so
  # only the two read paths can explain a difference, and the values are compared exactly.
  class CompareUsageService < BaseService
    Result = BaseResult[:rows, :differences, :compared_charges_count, :snapshot_charges_count, :rechecked]

    RECHECK_DELAY = 5.seconds

    Totals = Data.define(:units, :total_aggregated_units, :amount_cents, :events_count, :presentation_breakdowns)
    EMPTY_TOTALS = Totals.new(
      units: BigDecimal(0), total_aggregated_units: BigDecimal(0), amount_cents: 0, events_count: 0, presentation_breakdowns: {}
    )

    Row = Data.define(:charge_id, :billable_metric_code, :charge_filter_id, :grouped_by, :snapshot_read, :snapshot, :full_scan) do
      # Without a snapshot both runs scan the full history: a difference there is an event ingested
      # between them, never a snapshot bug.
      def different?
        snapshot_read && snapshot != full_scan
      end
    end

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    # An event ingested between the two runs moves one of them only: a difference is computed again
    # once, after the ingestion had time to settle, and only one that persists is reported.
    def call
      result.rechecked = false
      result.compared_charges_count = compared_charges.size
      result.snapshot_charges_count = snapshot_keys.map(&:first).uniq.size
      compare

      if result.differences.any?
        sleep(RECHECK_DELAY)
        result.rechecked = true
        compare
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e.result.error)
    end

    private

    attr_reader :subscription, :timestamp

    def compare
      result.rows = []
      result.differences = []
      return if snapshot_keys.empty?

      snapshot_usage = RecurringAggregationSnapshots.with_forced_read(true) { compute_usage }
      full_scan_usage = RecurringAggregationSnapshots.with_forced_read(false) { compute_usage }

      result.rows = build_rows(snapshot_usage:, full_scan_usage:)
      result.differences = result.rows.select(&:different?)
    end

    # Without the cache the incremental scan stays off, which would otherwise serve the recurring
    # sum on both sides and compare the scan with itself.
    def compute_usage
      Invoices::CustomerUsageService.call!(
        customer: subscription.customer,
        subscription:,
        timestamp:,
        with_cache: false,
        apply_taxes: false,
        usage_filters: UsageFilters.new(filter_by_charge_id: compared_charges.map(&:id))
      ).usage
    end

    def build_rows(snapshot_usage:, full_scan_usage:)
      snapshot_totals = totals_by_key(snapshot_usage)
      full_scan_totals = totals_by_key(full_scan_usage)

      (snapshot_totals.keys | full_scan_totals.keys).map do |key|
        charge_id, charge_filter_id, grouped_by = key

        Row.new(
          charge_id:,
          billable_metric_code: charges_by_id[charge_id].billable_metric.code,
          charge_filter_id:,
          grouped_by:,
          snapshot_read: snapshot_keys.include?([charge_id, charge_filter_id]),
          snapshot: snapshot_totals[key] || EMPTY_TOTALS,
          full_scan: full_scan_totals[key] || EMPTY_TOTALS
        )
      end
    end

    def totals_by_key(usage)
      (usage&.fees || []).each_with_object({}) do |fee, totals|
        key = [fee.charge_id, fee.charge_filter_id, normalized_groups(fee)]
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

    def normalized_groups(fee)
      normalized_values(fee.grouped_by)
    end

    # The snapshot path reads group values back from JSON, the full scan from the events.
    def normalized_values(values)
      (values || {}).transform_values { it&.to_s }
    end

    # The (charge, charge filter) pairs the snapshot run starts from a snapshot, rejected as the
    # aggregators reject them. A pair without one scans its full history on both sides.
    # Buckets and their grouping keys come from Fees::ChargeService, which adds target_wallet_code.
    def snapshot_keys
      @snapshot_keys ||= compared_charges.flat_map do |charge|
        Fees::ChargeService::Sources::Charge.new(charge:, boundaries: nil).pricing_buckets.filter_map do |bucket|
          [charge.id, bucket.charge_filter&.id] if snapshot_read?(bucket)
        end
      end.to_set
    end

    # A bucket without usage at the period has no snapshot, yet starts from the period.
    def snapshot_read?(bucket)
      period = RecurringAggregationSnapshots::FetchService.call!(
        subscription:,
        charge: bucket.charge,
        charge_filter: bucket.charge_filter,
        grouped_by_keys: bucket.pricing_group_keys.presence,
        from_datetime: date_service.charges_from_datetime
      ).period
      return false unless period

      # BillableMetrics::Aggregations::WeightedSumService#latest_snapshots, SumService#delta_period
      from_datetime = date_service.charges_from_datetime
      !bucket.billable_metric.weighted_sum_agg? || period.to_datetime.between?(from_datetime - 1.second, from_datetime)
    end

    def compared_charges
      @compared_charges ||= subscription.plan.charges.includes(:billable_metric, :filters).select do |charge|
        charge.billable_metric.recurring? &&
          RecurringAggregationSnapshot::AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type)
      end
    end

    def charges_by_id
      @charges_by_id ||= compared_charges.index_by(&:id)
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true)
    end
  end
end
