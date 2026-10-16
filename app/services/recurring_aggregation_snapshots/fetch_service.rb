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
      marker, records = own_period || previous_subscription_period
      return result unless marker && [marker, *records].all? { same_grouped_by_keys?(it) }

      result.period = Period.new(to_datetime: marker.to_datetime, watermark: marker.watermark)
      result.snapshots = records.map { to_snapshot(it) }
      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime

    # A marker the filters changed since falls back to a full scan, not to the previous subscription
    def own_period
      marker = latest_marker
      return unless marker

      filters_changed = RecurringAggregationSnapshot.filters_changed_since?(
        organization_id: subscription.organization_id, charge_ids: charge.id, watermark: marker.watermark
      )
      return [] if filters_changed

      [marker, period_records(marker).to_a]
    end

    # An upgrade or downgrade keeps the external id, so the events counted by the previous
    # subscription are the ones this one reads.
    def previous_subscription_period
      subscription.previous_recurring_aggregation_snapshots.period(charge:, charge_filter:)
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
    def latest_marker
      charge_snapshots
        .where(charge_filter_id: nil, to_datetime: ...from_datetime)
        .order(to_datetime: :desc, watermark: :desc)
        .first
    end

    # Rows of an older watermark belong to an overlapping run of the period, not to the marker's
    def period_records(marker)
      charge_snapshots.where(charge_filter_id: charge_filter&.id, to_datetime: marker.to_datetime, watermark: marker.watermark)
    end

    # Snapshots grouped on other keys cannot be regrouped, only a full scan can
    def same_grouped_by_keys?(record)
      record.grouped_by.keys.sort == Array(grouped_by_keys).map(&:to_s).sort
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
