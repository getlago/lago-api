# frozen_string_literal: true

module RecurringAggregationSnapshots
  class FetchService < BaseService
    Snapshot = Data.define(:grouped_by, :units, :events_count, :presentation_breakdowns, :to_datetime, :watermark) do
      def initialize(events_count: 0, presentation_breakdowns: [], **)
        super
      end
    end

    Period = Data.define(:to_datetime, :watermark)

    Result = BaseResult[:snapshots, :period]

    # Invoicing and pay in advance both check it, so they start the same charge from the same units
    def self.readable?(metered_item:, billing_context:)
      metered_item.billable_metric.recurring? &&
        RecurringAggregationSnapshot.eligible?(metered_item:, billing_context:) &&
        billing_context.organization.feature_flag_enabled?(:persisted_recurring_values)
    end

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
      period_records = latest_period_records.to_a
      marker = period_records.find { it.charge_filter_id.nil? }
      return result unless marker && !filters_changed_since?(marker)

      records = period_records.select { it.charge_filter_id == charge_filter&.id }
      return result unless records.all? { same_grouped_by_keys?(it) }
      return result if records.empty? && filter_edited_since?(marker)

      result.period = Period.new(to_datetime: marker.to_datetime, watermark: marker.watermark)
      result.snapshots = records.map { to_snapshot(it) }
      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime

    def charge_snapshots
      RecurringAggregationSnapshot.where(
        organization_id: subscription.organization_id,
        subscription_id: subscription.id,
        charge_id: charge.id
      )
    end

    # The default bucket keeps a row for every closed period, other buckets only for groups with
    # units or events: the marker tells a bucket without usage from a period never closed.
    # One statement reads the marker and the bucket, so a run rewriting the period cannot land in between.
    def latest_period_records
      latest_to_datetime = charge_snapshots
        .where(charge_filter_id: nil, to_datetime: ...from_datetime)
        .order(to_datetime: :desc)
        .limit(1)
        .select(:to_datetime)

      charge_snapshots.where(charge_filter_id: [nil, charge_filter&.id].uniq, to_datetime: latest_to_datetime)
    end

    # A filter or filter value created, edited or removed since the marker moves older events between
    # buckets, so the snapshots of every bucket of the charge are stale, not only the one of that filter.
    # A value set to all values reads the metric filter's values, which change without touching it.
    def filters_changed_since?(marker)
      charge_filters = ChargeFilter.with_discarded.unscope(:order)
        .where(organization_id: subscription.organization_id, charge_id: charge.id)
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

    # Snapshots grouped on other keys cannot be regrouped, only a full scan can. Checked on the
    # bucket's own rows, as a filter can group on other keys than the default bucket holding the marker.
    def same_grouped_by_keys?(record)
      record.grouped_by.keys.sort == Array(grouped_by_keys).map(&:to_s).sort
    end

    # An empty bucket has no row to compare grouping keys with, and an edit of the filter's
    # properties can regroup units that netted to zero into non-zero groups
    def filter_edited_since?(marker)
      charge_filter.present? && charge_filter.updated_at > marker.watermark
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
