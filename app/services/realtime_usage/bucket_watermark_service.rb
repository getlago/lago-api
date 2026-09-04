# frozen_string_literal: true

module RealtimeUsage
  # Which subscriptions' ClickHouse usage buckets have caught up with the ingestion watermark
  # carried by their realtime usage trigger.
  #
  # The trigger and the bucket upsert are two sinks of the same stream epoch with no
  # cross-sink ordering guarantee, so a reaction dispatched on the trigger alone would read
  # the previous epoch's usage — for wallet refresh, debiting the wallet against it.
  class BucketWatermarkService < BaseService
    Result = BaseResult[:caught_up_subscription_ids]

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

    # One read for the whole set: a trigger batch carries thousands of subscriptions and is
    # re-read on every pause cycle, so a round-trip per subscription would cost more time than
    # the ingestion it reacts to.
    #
    # `organization_id` leads the conditions because it leads the table's sorting key. Without
    # it the read cannot use the key at all, and answering "did the buckets land yet" then
    # costs a partition scan on every poll.
    #
    # `unscoped` drops the model's FINAL: `last_ingested_at` is the version column, so
    # collapsing versions can only raise the maximum, and a subscription cannot flip from
    # caught up back to behind.
    #
    # Integer milliseconds on both sides: converting the stored timestamp through a float can
    # land it a microsecond above the watermark and make `>=` unsatisfiable, so the wait could
    # only ever time out.
    #
    # `uncached` because Karafka consumes inside the Rails executor, which enables the
    # ActiveRecord query cache: a read that ran before the buckets landed would otherwise be
    # replayed from cache for the rest of the pause cycle.
    def stored_watermarks_ms
      Clickhouse::UsageBucket.uncached do
        Clickhouse::UsageBucket
          .unscoped
          .where(organization_id: watermarks.pluck(:organization_id).uniq)
          .where(subscription_id: expected_watermarks_ms.keys)
          .group(:subscription_id)
          .maximum(Arel.sql("toUnixTimestamp64Milli(last_ingested_at)"))
      end
    end
  end
end
