# frozen_string_literal: true

module RecurringAggregationSnapshots
  class PersistService < BaseService
    Result = BaseResult

    # Reads take the latest period, and a draft refreshed during its grace period the one before it. The third is left to the audit.
    KEPT_PERIODS = 3

    # key: a SubscriptionKey or ContractKey
    # buckets: one {filter:, values:} per pricing bucket of the key
    # values: one {grouped_by:, units:, events_count:, presentation_breakdowns:} per group of the bucket
    def initialize(key:, to_datetime:, watermark:, buckets:)
      @key = key
      @to_datetime = to_datetime
      @watermark = watermark
      @buckets = buckets

      super
    end

    def call
      # Without it, a run with an older watermark could insert a group a newer run left out.
      # Held until the outer transaction commits: the whole invoice when called while invoicing.
      LockService.call!(key:, to_datetime:) do
        # Overlapping runs of the same period: the latest watermark has seen the most events.
        # Checked on the whole key, as an empty filter leaves no row holding the watermark of its run.
        next if period_snapshots.exists?(["watermark > ?", watermark])

        # A group or filter missing from a later run of the period dropped to zero units
        period_snapshots.delete_all
        key.model.insert_all(rows, returning: false) if rows.any? # rubocop:disable Rails/SkipsModelValidations
        older_periods_snapshots.delete_all
      end

      result
    end

    private

    attr_reader :key, :to_datetime, :watermark, :buckets

    def period_snapshots
      key.snapshots.where(to_datetime:)
    end

    # Counted from the latest markers rather than the period written, as a draft refresh rewrites an older one
    def older_periods_snapshots
      oldest_kept_period = key.snapshots.period_markers.distinct
        .order(to_datetime: :desc).offset(KEPT_PERIODS - 1).limit(1).select(:to_datetime)

      key.snapshots.where(
        key.model.arel_table[:to_datetime].lt(Arel::Nodes::Grouping.new(oldest_kept_period.arel))
      )
    end

    def rows
      @rows ||= buckets.flat_map do |bucket|
        bucket[:values].map do |value|
          {
            **key.row_attributes,
            key.model::BUCKET_COLUMN => key.bucket_id(bucket[:filter]),
            :grouped_by => value[:grouped_by] || {},
            :to_datetime => to_datetime,
            :watermark => watermark,
            :units => value[:units],
            :events_count => value[:events_count] || 0,
            :presentation_breakdowns => value[:presentation_breakdowns] || []
          }
        end
      end
    end
  end
end
