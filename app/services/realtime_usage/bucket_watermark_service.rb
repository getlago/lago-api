# frozen_string_literal: true

module RealtimeUsage
  # Which subscriptions' usage buckets have caught up with their trigger's ingestion watermark.
  # Trigger and bucket are two sinks of one epoch, with no ordering guaranteed between them.
  class BucketWatermarkService < BaseService
    Result = BaseResult[:caught_up_subscription_ids]

    # How far below the watermark the read still looks. Without a floor it fans out over every
    # month the subscription has buckets for; an event this late instead waits for the sweep.
    BUCKET_GRACE = 2.days

    # @param watermarks [Array<Hash>] one entry per subscription to check, each carrying
    #   `organization_id`, `subscription_id` and `watermark_ms`
    def initialize(watermarks:)
      @watermarks = watermarks

      super
    end

    def call
      result.caught_up_subscription_ids = caught_up_subscription_ids
      result
    end

    private

    attr_reader :watermarks

    # Integer milliseconds on both sides: a stored timestamp converted through a float can land
    # a microsecond above the watermark and make `>=` unsatisfiable.
    def caught_up_subscription_ids
      stored_watermarks_ms.filter_map do |subscription_id, stored_ms|
        subscription_id if stored_ms.to_i >= expected_watermarks_ms[subscription_id]
      end.to_set
    end

    # The highest watermark wins: a subscription caught up with it is caught up with every
    # lower one, so the wait cannot be cut short by an entry left behind.
    def expected_watermarks_ms
      @expected_watermarks_ms ||= watermarks
        .group_by { it[:subscription_id] }
        .transform_values { |entries| entries.pluck(:watermark_ms).max }
    end

    # One read for the whole set, `organization_id` first because it leads the table's sorting
    # key: without it, answering "did the buckets land" costs a sort-key scan on every poll.
    def stored_watermarks_ms
      # `uncached` because the executor's query cache would replay a read from before the
      # buckets landed; `unscoped` drops FINAL, which can only raise the version column's max.
      Clickhouse::UsageBucket.uncached do
        Clickhouse::UsageBucket
          .unscoped
          .where(organization_id: watermarks.pluck(:organization_id).uniq)
          .where(subscription_id: expected_watermarks_ms.keys)
          .where(bucket: bucket_floor..)
          # A tombstone carries the highest version by construction, so counting one would read
          # as caught up on usage that no longer exists.
          .where(is_deleted: 0)
          .group(:subscription_id)
          .maximum(Arel.sql("toUnixTimestamp64Milli(last_ingested_at)"))
      end
    end

    # `bucket` is the partition key, so this is what keeps the read off every other month.
    def bucket_floor
      @bucket_floor ||= Time.zone.at(Rational(watermarks.pluck(:watermark_ms).min, 1000)) - BUCKET_GRACE
    end
  end
end
