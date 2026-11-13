# frozen_string_literal: true

module RecurringAggregationSnapshots
  # CompareUsageService for a contract: computes its current usage twice, once starting the recurring
  # products from their snapshots and once scanning their full history, and compares them per
  # (product, product filter, group). Contract usage has no charge cache, so only the two read paths
  # can explain a difference.
  class CompareContractUsageService < BaseService
    include UsageComparison

    Result = BaseResult[:rows, :differences, :compared_items_count, :snapshot_items_count, :rechecked]

    RECHECK_DELAY = 5.seconds

    def initialize(contract:, timestamp: Time.current)
      @contract = contract
      @timestamp = timestamp

      super
    end

    # An event ingested between the two runs moves one of them only: a difference is computed again
    # once, after the ingestion had time to settle, and only one that persists is reported.
    def call
      result.rechecked = false
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

    attr_reader :contract, :timestamp, :snapshot_keys

    # The segments open at the timestamp come from the usage: the full scan runs first and tells
    # which of them start from a snapshot, and the snapshot run only follows when one does.
    def compare
      result.rows = []
      result.differences = []

      full_scan_usages = RecurringAggregationSnapshots.with_forced_read(false) { compute_usages }
      @snapshot_keys = full_scan_usages.filter_map { leaf_key(it) if snapshot_read?(it.billing_segment) }.to_set
      result.compared_items_count = full_scan_usages.map { leaf_key(it).first }.uniq.size
      result.snapshot_items_count = snapshot_keys.map(&:first).uniq.size
      return if snapshot_keys.empty?

      snapshot_usages = RecurringAggregationSnapshots.with_forced_read(true) { compute_usages }

      result.rows = build_rows(snapshot_leaves: leaves(snapshot_usages), full_scan_leaves: leaves(full_scan_usages))
      result.differences = result.rows.select(&:different?)
    end

    # Filtered on the compared products, which an empty filter would not narrow
    def compute_usages
      return [] if compared_products.empty?

      Contracts::CurrentUsageService.call!(
        contract:,
        timestamp:,
        apply_taxes: false,
        filters: {product_ids: compared_products.map(&:id)}
      ).rate_card_usages
    end

    def leaves(usages)
      usages.flat_map do |usage|
        product_id, product_filter_id = leaf_key(usage)
        usage.fees.map { [product_id, product_filter_id, it] }
      end
    end

    def leaf_key(usage)
      rate_card = usage.contract_rate_card.rate_card
      [rate_card.product_id, rate_card.product_filter_id]
    end

    def billable_metric_code(product_id)
      compared_products.find { it.id == product_id }.billable_metric.code
    end

    # A card prices a single bucket, its product filter. A bucket without usage at the period has no
    # snapshot, yet starts from the period.
    def snapshot_read?(billing_segment)
      Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:).pricing_buckets.any? do |bucket|
        period = RecurringAggregationSnapshots::FetchService.call!(
          **RecurringAggregationSnapshot.fetch_arguments(
            metered_item: bucket, billing_context:, grouped_by_keys: bucket.pricing_group_keys.presence
          )
        ).period

        period.present? && starts_from_period?(bucket.billable_metric, period, billing_segment.started_at)
      end
    end

    def compared_products
      # Discarded products and rate cards are still priced by the cards applied to the contract
      @compared_products ||= Product.with_discarded.metered
        .where(
          organization_id: contract.organization_id,
          id: RateCard.with_discarded.where(id: contract.applied_rate_cards.select(:rate_card_id)).select(:product_id)
        )
        .includes(:billable_metric)
        .select do |product|
          product.billable_metric.recurring? &&
            RecurringAggregationSnapshot::AGGREGATION_TYPES.include?(product.billable_metric.aggregation_type)
        end
    end

    def billing_context
      @billing_context ||= Billing::Context.from(contract:)
    end
  end
end
