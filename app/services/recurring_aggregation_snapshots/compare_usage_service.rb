# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Computes the current usage of one subscription twice, once starting the recurring charges from
  # their snapshots and once scanning their full history, and compares them per
  # (charge, charge filter, group). Both runs share one timestamp and skip the charge caches, so
  # only the two read paths can explain a difference, and the values are compared exactly.
  class CompareUsageService < BaseService
    include UsageComparison

    Result = BaseResult[:rows, :differences, :compared_items_count, :snapshot_items_count, :rechecked]

    RECHECK_DELAY = 5.seconds

    def initialize(subscription:, timestamp: Time.current)
      @subscription = subscription
      @timestamp = timestamp

      super
    end

    # An event ingested between the two runs moves one of them only: a difference is computed again
    # once, after the ingestion had time to settle, and only one that persists is reported.
    def call
      result.rechecked = false
      result.compared_items_count = compared_charges.size
      result.snapshot_items_count = snapshot_keys.map(&:first).uniq.size
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

      result.rows = build_rows(snapshot_leaves: leaves(snapshot_usage), full_scan_leaves: leaves(full_scan_usage))
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

    def leaves(usage)
      (usage&.fees || []).map { [it.charge_id, it.charge_filter_id, it] }
    end

    def billable_metric_code(charge_id)
      charges_by_id[charge_id].billable_metric.code
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
        key: RecurringAggregationSnapshots::SubscriptionKey.new(subscription:, charge: bucket.charge),
        filter: bucket.charge_filter,
        grouped_by_keys: bucket.pricing_group_keys.presence,
        from_datetime: date_service.charges_from_datetime
      ).period
      return false unless period

      starts_from_period?(bucket.billable_metric, period, date_service.charges_from_datetime)
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
