# frozen_string_literal: true

module RecurringAggregationSnapshots
  class FetchService < BaseService
    Snapshot = Data.define(:grouped_by, :units, :events_count, :presentation_breakdowns, :to_datetime, :watermark) do
      def initialize(events_count: 0, presentation_breakdowns: [], **)
        super
      end
    end

    Period = Data.define(:to_datetime, :watermark)

    # The snapshots of one bucket: this subscription's, or the matching one of the previous subscription
    Bucket = Data.define(:subscription_id, :charge_id, :charge_filter, :before)

    Result = BaseResult[:snapshots, :period]

    def initialize(subscription:, charge:, charge_filter:, grouped_by_keys:, from_datetime:)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @grouped_by_keys = grouped_by_keys
      @from_datetime = from_datetime

      super
    end

    # Returns the snapshots of the latest period closed before from_datetime, one per group with
    # units or events, and that period. Both are nil when the aggregation must fall back to a full scan.
    def call
      bucket = own_bucket
      period_records = latest_period_records(bucket).to_a

      if period_records.empty?
        bucket = previous_subscription_bucket
        period_records = latest_period_records(bucket).to_a if bucket
      end
      marker = period_records.find { it.charge_filter_id.nil? }
      return result unless marker && !filters_changed_since?(bucket, marker)

      records = period_records.select { it.charge_filter_id == bucket.charge_filter&.id }
      return result unless records.all? { same_grouped_by_keys?(it) }
      return result if records.empty? && regrouped_since?(bucket.charge_filter, marker)

      result.period = Period.new(to_datetime: marker.to_datetime, watermark: marker.watermark)
      result.snapshots = records.map { to_snapshot(it) }
      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime

    def own_bucket
      Bucket.new(subscription_id: subscription.id, charge_id: charge.id, charge_filter:, before: from_datetime)
    end

    def charge_snapshots(bucket)
      RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: bucket.subscription_id,
        charge_id: bucket.charge_id
      )
    end

    # The default bucket keeps a row for every closed period, other buckets only for groups with
    # units or events: the marker tells a bucket without usage from a period never closed.
    # One statement reads the marker and the bucket, so a run rewriting the period cannot land in between.
    def latest_period_records(bucket)
      latest_to_datetime = charge_snapshots(bucket).where(charge_filter_id: nil)
      latest_to_datetime = latest_to_datetime.where(to_datetime: ...bucket.before) if bucket.before
      latest_to_datetime = latest_to_datetime.order(to_datetime: :desc).limit(1).select(:to_datetime)

      charge_snapshots(bucket).where(charge_filter_id: [nil, bucket.charge_filter&.id].uniq, to_datetime: latest_to_datetime)
    end

    # A filter or filter value created, edited or removed since the marker moves older events between
    # buckets, so the snapshots of every bucket of the charge are stale, not only the one of that filter.
    # A value set to all values reads the metric filter's values, which change without touching it.
    # From the previous subscription, only its charge counts: the current filters match it by signature.
    def filters_changed_since?(bucket, marker)
      charge_filters = ChargeFilter.with_discarded.unscope(:order)
        .where(organization_id: subscription.organization_id, charge_id: bucket.charge_id)
      charge_filter_values = ChargeFilterValue.with_discarded.unscope(:order)
        .where(organization_id: subscription.organization_id, charge_filter_id: charge_filters.select(:id))

      charge_filters.where("created_at > :watermark OR deleted_at > :watermark", watermark: marker.watermark).exists? ||
        charge_filter_values.where("updated_at > :watermark OR deleted_at > :watermark", watermark: marker.watermark).exists? ||
        BillableMetricFilter.with_discarded.unscope(:order)
          .where(
            organization_id: subscription.organization_id,
            id: charge_filter_values.where(values: [ChargeFilterValue::ALL_FILTER_VALUES]).select(:billable_metric_filter_id)
          )
          .where("updated_at > :watermark OR deleted_at > :watermark", watermark: marker.watermark)
          .exists?
    end

    # An upgrade or downgrade keeps the external id, so the events counted by the previous
    # subscription are the ones this one reads. Its snapshots close at the termination, which an
    # upgrade stamps just after this subscription starts: they are not bounded by from_datetime.
    def previous_subscription_bucket
      return unless subscription.previous_subscription_id

      # Two matching charges would read the same events, but a plan with both is ambiguous enough
      # to pay one full scan rather than guess
      matching_charges = previous_charges
      return unless matching_charges.one?

      previous_charge = matching_charges.first
      previous_filter = matching_previous_filter(previous_charge)
      return if !default_bucket? && previous_filter.nil?

      Bucket.new(
        subscription_id: subscription.previous_subscription_id,
        charge_id: previous_charge.id,
        charge_filter: previous_filter,
        before: nil
      )
    end

    # Weighted sum stores its breakdowns per presentation group, which only the same keys can read.
    # A discarded charge is skipped, its filters are discarded with it and would no longer tell its buckets apart.
    def previous_charges
      charge_ids = RecurringAggregationSnapshot
        .where(
          organization_id: subscription.organization_id,
          subscription_id: subscription.previous_subscription_id,
          billable_metric_id: charge.billable_metric_id
        )
        .distinct
        .select(:charge_id)

      Charge
        .where(organization_id: subscription.organization_id, id: charge_ids)
        .includes(filters: {values: :billable_metric_filter})
        .select do |previous_charge|
          filters_signature(previous_charge) == filters_signature(charge) &&
            previous_charge.presentation_group_keys_values.sort == charge.presentation_group_keys_values.sort
        end
    end

    def matching_previous_filter(previous_charge)
      return if default_bucket?

      signature = bucket_signatures(charge)[charge_filter.id]
      previous_charge.filters.find { bucket_signatures(previous_charge)[it.id] == signature }
    end

    def filters_signature(target_charge)
      bucket_signatures(target_charge).values.to_set
    end

    # An event goes to the matching filter of highest precedence: a bucket holds the same events on
    # both charges when its filter and the overlapping filters taking precedence over it are the same
    def bucket_signatures(target_charge)
      @bucket_signatures ||= {}
      @bucket_signatures[target_charge.id] ||= target_charge.filters.to_h do |filter|
        preceding = target_charge.filters.select { preceding_overlap?(it, filter) }
        [filter.id, [filter_signature(filter), preceding.map { filter_signature(it) }.tally]]
      end
    end

    def preceding_overlap?(other, filter)
      values = filter.to_h_with_all_values

      (other.precedence <=> filter.precedence).negative? &&
        other.to_h_with_all_values.all? { |key, other_values| !values.key?(key) || other_values.intersect?(values[key]) }
    end

    def filter_signature(filter)
      filter.to_h.transform_values(&:sort)
    end

    def default_bucket?
      !charge_filter&.persisted?
    end

    # Snapshots grouped on other keys cannot be regrouped, only a full scan can. Checked on the
    # bucket's own rows, as a filter can group on other keys than the default bucket holding the marker.
    def same_grouped_by_keys?(record)
      record.grouped_by.keys.sort == Array(grouped_by_keys).map(&:to_s).sort
    end

    # An empty bucket has no row to compare grouping keys with: an edit of the filter's properties, or a
    # previous filter grouped on other keys, can regroup units that netted to zero into non-zero groups
    def regrouped_since?(bucket_filter, marker)
      bucket_filter.present? &&
        (bucket_filter.updated_at > marker.watermark || (bucket_filter != charge_filter && !same_grouping?(bucket_filter)))
    end

    def same_grouping?(previous_filter)
      Array(previous_filter.pricing_group_keys).sort == Array(charge_filter.pricing_group_keys).sort &&
        previous_filter.charge.accepts_target_wallet == charge.accepts_target_wallet
    end

    def to_snapshot(record)
      Snapshot.new(
        grouped_by: record.grouped_by.freeze,
        units: record.units,
        events_count: record.events_count,
        presentation_breakdowns: record.presentation_breakdowns.map { it.symbolize_keys.freeze }.freeze,
        to_datetime: record.to_datetime,
        watermark: record.watermark
      )
    end
  end
end
