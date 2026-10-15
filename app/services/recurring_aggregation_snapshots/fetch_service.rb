# frozen_string_literal: true

module RecurringAggregationSnapshots
  class FetchService < BaseService
    Snapshot = Data.define(:grouped_by, :units, :to_datetime, :watermark)

    Result = BaseResult[:snapshots]

    def initialize(subscription:, charge:, charge_filter:, grouped_by_keys:, from_datetime:)
      @subscription = subscription
      @charge = charge
      @charge_filter = charge_filter
      @grouped_by_keys = grouped_by_keys
      @from_datetime = from_datetime

      super
    end

    # Returns the snapshots of the latest period closed before from_datetime, one per group,
    # or nil when the aggregation must fall back to a full scan.
    def call
      records = latest_records.to_a

      result.snapshots = if records.any? && records.all? { |record| same_grouped_by_keys?(record) }
        records.map { |record| to_snapshot(record) }
      end

      result
    end

    private

    attr_reader :subscription, :charge, :charge_filter, :grouped_by_keys, :from_datetime

    def latest_records
      scope = RecurringAggregationSnapshot.where(
        subscription_id: subscription.id,
        charge_id: charge.id,
        charge_filter_id: charge_filter&.persisted? ? charge_filter.id : nil
      ).where(to_datetime: ...from_datetime)

      scope.where(to_datetime: scope.select("MAX(to_datetime)"))
    end

    # Snapshots grouped on other keys cannot be regrouped, only a full scan can
    def same_grouped_by_keys?(record)
      record.grouped_by.keys.sort == Array(grouped_by_keys).map(&:to_s).sort
    end

    def to_snapshot(record)
      Snapshot.new(
        grouped_by: record.grouped_by.freeze,
        units: record.units,
        to_datetime: record.to_datetime,
        watermark: record.watermark
      )
    end
  end
end
