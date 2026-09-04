# frozen_string_literal: true

module RealtimeUsage
  # Whether the ClickHouse usage buckets of one subscription have caught up with the
  # ingestion watermark carried by a realtime usage trigger.
  #
  # The trigger and the bucket upsert are two sinks of the same stream epoch with no
  # cross-sink ordering guarantee, so a reaction dispatched on the trigger alone would read
  # the previous epoch's usage — for wallet refresh, debiting the wallet against it.
  class BucketWatermarkService < BaseService
    Result = BaseResult[:reached]

    def initialize(organization_id:, subscription_id:, watermark_ms:)
      @organization_id = organization_id
      @subscription_id = subscription_id
      @watermark_ms = watermark_ms

      super
    end

    def call
      result.reached = reached?
      result
    end

    private

    attr_reader :organization_id, :subscription_id, :watermark_ms

    # `uncached` because Karafka consumes inside the Rails executor, which enables the
    # ActiveRecord query cache: a poll that ran before the bucket landed would otherwise be
    # replayed from cache for every later message of the batch.
    def reached?
      Clickhouse::UsageBucket.uncached do
        buckets.exists?
      end
    end

    # `organization_id` leads the conditions because it leads the table's sorting key.
    # Without it the read cannot use the key at all, and answering "did the bucket land yet"
    # then costs a partition scan on every poll.
    #
    # `unscoped` drops the model's FINAL: `last_ingested_at` is the version column, so
    # collapsing versions can only raise it, and an existence test on `>=` cannot flip from
    # true to false.
    #
    # Integer milliseconds on both sides: converting the stored timestamp through a float can
    # land it a microsecond above the watermark and make `>=` unsatisfiable, so the wait
    # could only ever time out.
    def buckets
      Clickhouse::UsageBucket
        .unscoped
        .where(organization_id:, subscription_id:)
        .where("toUnixTimestamp64Milli(last_ingested_at) >= ?", watermark_ms)
    end
  end
end
