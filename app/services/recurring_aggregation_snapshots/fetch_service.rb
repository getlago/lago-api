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

    # charge_period: a ChargePeriod shared by the charge filters of the charge, loaded once for all of them
    # grouped_by_values: returns only the snapshots of that group, as pay in advance reads one group
    # all_buckets: false loads only the charge filter's bucket, as pay in advance reads one
    def initialize(
      subscription:, charge:, charge_filter:, grouped_by_keys:, from_datetime:, charge_period: nil, grouped_by_values: nil, all_buckets: true
    )
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @grouped_by_keys = grouped_by_keys
      @from_datetime = from_datetime
      @grouped_by_values = grouped_by_values && normalized_group(grouped_by_values)
      @charge_period = charge_period || ChargePeriod.new(
        subscription:, charge:, from_datetime:, grouped_by_values:, charge_filter_ids: (all_buckets ? nil : [charge_filter&.id].compact)
      )
      @all_buckets = all_buckets

      super
    end

    # Returns the snapshots of the latest period closed before from_datetime, one per group with
    # units or events, and that period. Both are nil when the aggregation must fall back to a full scan.
    def call
      marker, records = own_period || previous_subscription_period
      return result unless marker && records.all? { same_grouped_by_keys?(it) }

      result.period = Period.new(to_datetime: marker.to_datetime, watermark: marker.watermark)
      result.snapshots = records.select { in_group?(it) }.map { to_snapshot(it) }
      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime, :charge_period, :grouped_by_values, :all_buckets

    def own_period
      period = charge_period.period(charge_filter:)
      marker, records = period
      (marker && records.empty? && filter_edited_since?(marker)) ? [] : period
    end

    # An upgrade or downgrade keeps the external id, so the events counted by the previous
    # subscription are the ones this one reads.
    def previous_subscription_period
      subscription.previous_recurring_aggregation_snapshots.period(charge:, charge_filter:, all_buckets:)
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

    # A group without a snapshot had neither units nor events at the period, so it starts from zero.
    # A key left out, such as the target wallet of an event targeting none, matches every value.
    def in_group?(record)
      grouped_by_values.nil? || normalized_group(record.grouped_by.slice(*grouped_by_values.keys)) == grouped_by_values
    end

    # The stores group a blank value with a missing one, so a snapshot holds an event's "" as nil
    def normalized_group(grouped_by)
      grouped_by.to_h { |key, value| [key.to_s, value&.to_s.presence] }
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
