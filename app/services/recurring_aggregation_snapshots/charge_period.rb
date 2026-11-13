# frozen_string_literal: true

module RecurringAggregationSnapshots
  # The latest period of a key closed before from_datetime. Loads the marker, the filter check
  # and the snapshots once, for all the key's buckets.
  class ChargePeriod
    # filter_ids: the buckets to load besides the marker's, every bucket of the key when nil
    # grouped_by_values: loads only the snapshots of that group, plus one per bucket (see of_group)
    # period_attributes: column values the marker must hold, as the period was closed with them
    def initialize(key:, from_datetime:, filter_ids: nil, grouped_by_values: nil, grouped_by_keys: [], period_attributes: {})
      @key = key
      @from_datetime = from_datetime
      @filter_ids = filter_ids
      @grouped_by_values = grouped_by_values
      @grouped_by_keys = grouped_by_keys
      @period_attributes = period_attributes
    end

    # Marker and snapshots of the filter's bucket, or nil without a marker. A marker closed with other
    # period attributes, or the filters changed since, gives [], a full scan rather than the previous owner's period.
    def period(filter:)
      return unless marker

      if period_attributes.any? { |column, value| marker[column] != value } || filters_changed?
        []
      else
        [marker, records.fetch(filter&.id, [])]
      end
    end

    def all_buckets?
      filter_ids.nil?
    end

    private

    attr_reader :key, :from_datetime, :filter_ids, :grouped_by_values, :grouped_by_keys, :period_attributes

    # The marker bucket keeps a row for every closed period, other buckets only for groups with
    # units or events: the marker tells a bucket without usage from a period never closed.
    def marker
      records[key.marker_bucket_id]&.first
    end

    # Listing the buckets lets the period index serve to_datetime too
    def records
      @records ||= begin
        bucket_ids = key.bucket_ids(filter_ids)
        key.snapshots.latest_period(bucket_ids, before: from_datetime)
          .of_group(grouped_by_values, grouped_by_keys:, bucket_ids:)
          .group_by { it[key.model::BUCKET_COLUMN] }
      end
    end

    def filters_changed?
      return @filters_changed if defined?(@filters_changed)

      @filters_changed = key.filters_changed_since?(marker.watermark)
    end
  end
end
