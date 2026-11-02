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

    # all_buckets: false loads only the charge filter's bucket of the previous subscription, as pay in advance reads one
    def initialize(subscription:, charge:, charge_filter:, grouped_by_keys:, from_datetime:, all_buckets: true)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @grouped_by_keys = grouped_by_keys
      @from_datetime = from_datetime
      @all_buckets = all_buckets

      super
    end

    # Returns the snapshots of the latest period closed before from_datetime, one per group with
    # units or events, and that period. Both are nil when the aggregation must fall back to a full scan.
    def call
      marker, records = own_period || previous_subscription_period
      return result unless marker && records.all? { same_grouped_by_keys?(it) }

      result.period = Period.new(to_datetime: marker.to_datetime, watermark: marker.watermark)
      result.snapshots = records.map { to_snapshot(it) }
      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime, :all_buckets

    # A marker the filters changed since falls back to a full scan, not to the previous subscription
    def own_period
      period_records = latest_period_records.to_a
      marker = period_records.find { it.charge_filter_id.nil? }
      return unless marker

      filters_changed = RecurringAggregationSnapshot.filters_changed_since?(
        organization_id: subscription.organization_id, charge_ids: charge.id, watermark: marker.watermark
      )
      return [] if filters_changed

      records = period_records.select { it.charge_filter_id == charge_filter&.id }
      (records.empty? && filter_edited_since?(marker)) ? [] : [marker, records]
    end

    # An upgrade or downgrade keeps the external id, so the events counted by the previous
    # subscription are the ones this one reads.
    def previous_subscription_period
      subscription.previous_recurring_aggregation_snapshots.period(charge:, charge_filter:, all_buckets:)
    end

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

      charge_snapshots.where(charge_filter_id: [nil, charge_filter&.id].uniq).of_period(latest_to_datetime)
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
