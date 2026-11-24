# frozen_string_literal: true

module RealtimeUsage
  # Trigger and bucket upsert are two sinks of the same RisingWave epoch, unordered between
  # them: without the wait a fast consumer reads the previous epoch's usage.
  class BucketWatermark
    TIMEOUT = 5.seconds
    INTERVAL = 0.1
    STALE_CUTOFF = 30.seconds

    # Replicas apply a write seconds apart, so a read after the wait could land on one that lacks the
    # bucket the wait saw. On SharedMergeTree the replica syncs its parts first; elsewhere it is a no-op.
    CONSISTENT_READ_SETTINGS = {select_sequential_consistency: 1}.freeze

    def self.consistent_reads(&)
      ::Clickhouse::BaseRecord.with_connection do |connection|
        connection.with_settings(**CONSISTENT_READ_SETTINGS, &)
      end
    end

    # pending maps subscription ids to the trigger watermark in milliseconds. Returns nil once every
    # subscription's buckets reached it, otherwise the reason it gave up (:stale_watermark, :bucket_wait_timeout).
    def self.wait(organization_id:, pending:, lane:)
      new(organization_id:, pending:, lane:).wait
    end

    def initialize(organization_id:, pending:, lane:)
      @organization_id = organization_id
      @pending = pending.dup
      @lane = lane
    end

    def wait
      return nil if pending.empty?

      started_at = Time.current
      reason = self.class.consistent_reads { poll }
      Yabeda.realtime_usage.bucket_wait.measure({lane:}, Time.current - started_at)
      reason
    end

    private

    attr_reader :organization_id, :pending, :lane

    def poll
      stale_cutoff_ms = ((Time.current - STALE_CUTOFF).to_f * 1000).to_i
      deadline = Time.current + TIMEOUT

      loop do
        pending.delete_if { |subscription_id, watermark_ms| caught_up?(subscription_id, watermark_ms) }
        return nil if pending.empty?

        # An old watermark means the consumer is behind, not ClickHouse: sleeping on it spends the
        # batch's deadline for nothing, so it gets one check and goes back to the sweep.
        stale = pending.select { |_sub, ms| ms.to_i < stale_cutoff_ms }
        if stale.any?
          log_pending("usage buckets behind a stale watermark", stale)
          return :stale_watermark
        end

        if Time.current > deadline
          log_pending("usage buckets did not catch up", pending)
          return :bucket_wait_timeout
        end

        sleep INTERVAL
      end
    end

    def caught_up?(subscription_id, watermark_ms)
      # unscoped: any row version at the watermark proves the epoch landed, and FINAL would be
      # paid every cycle. uncached: the executor turns the AR query cache on, and a cached miss
      # can only time out. organization_id leads the ORDER BY, without it there is no key scan.
      Clickhouse::UsageBucket.uncached do
        Clickhouse::UsageBucket
          .unscoped
          .where(organization_id:, subscription_id:)
          .where("toUnixTimestamp64Milli(last_ingested_at) >= ?", watermark_ms.to_i)
          .exists?
      end
    end

    def log_pending(reason, pending)
      Rails.logger.warn(
        "[realtime_usage] #{reason} lane=#{lane} organization_id=#{organization_id} pending=#{pending.keys.inspect}"
      )
    end
  end
end
