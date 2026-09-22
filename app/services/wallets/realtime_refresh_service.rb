# frozen_string_literal: true

module Wallets
  # wallet_codes carries the events' targeting intent (properties.target_wallet_code): it forces
  # the refresh, it does not narrow it — the allocation cascade makes wallets interdependent.
  class RealtimeRefreshService < BaseService
    # reason names the exit taken when no refresh happened, and is nil when one did. The consumer
    # counts it: these exits are the half of the partition it cannot see from the outside.
    Result = BaseResult[:wallets, :reason]

    # Trigger and bucket upsert are two sinks of the same RisingWave epoch, unordered between
    # them: without the wait a fast consumer reads the previous epoch's usage.
    BUCKET_WAIT_TIMEOUT = 5.seconds
    BUCKET_WAIT_INTERVAL = 0.1
    STALE_WATERMARK_CUTOFF = 30.seconds

    def initialize(organization_id:, customer_id:, wallet_codes: [], expected_ingested_at: {})
      @organization_id = organization_id
      @customer_id = customer_id
      @wallet_codes = wallet_codes
      @expected_ingested_at = expected_ingested_at

      super
    end

    def call
      result.wallets = []

      customer = Customer.find_by(id: customer_id, organization_id:)
      return skipped(:customer_not_found) if customer.nil?
      return skipped(:no_active_wallet) unless customer.wallets.active.exists?

      # Refreshing on buckets that have not caught up writes a stale balance and clears
      # awaiting_wallet_refresh, the flag the sweep selects on: nothing would correct it after.
      wait_reason = wait_for_buckets
      return skipped(wait_reason) if wait_reason

      if wallet_codes.present? && customer.wallets.active.where(code: wallet_codes).none?
        Yabeda.realtime_usage.wallet_refresh_unknown_codes_total.increment({})
        Rails.logger.warn(
          "[wallets] realtime refresh targeted unknown wallet codes " \
          "customer_id=#{customer.id} codes=#{wallet_codes.inspect}"
        )
      end

      refresh_result = Customers::RefreshWalletsService.call(customer:)
      return refresh_result unless refresh_result.success?

      result.wallets = refresh_result.wallets
      result
    end

    private

    attr_reader :organization_id, :customer_id, :wallet_codes, :expected_ingested_at

    def skipped(reason)
      result.reason = reason
      result
    end

    # Timed here rather than around each poll so the histogram carries the whole wait, including
    # the one that ends in a give-up: that tail is what says the buckets stopped moving.
    def wait_for_buckets
      return nil if expected_ingested_at.empty?

      started_at = Time.current
      reason = poll_buckets
      Yabeda.realtime_usage.wallet_refresh_bucket_wait.measure({}, Time.current - started_at)
      reason
    end

    def poll_buckets
      pending = expected_ingested_at.dup
      stale_cutoff_ms = ((Time.current - STALE_WATERMARK_CUTOFF).to_f * 1000).to_i
      deadline = Time.current + BUCKET_WAIT_TIMEOUT

      loop do
        pending.delete_if { |subscription_id, watermark_ms| bucket_caught_up?(subscription_id, watermark_ms) }
        return nil if pending.empty?

        # An old watermark means the consumer is behind, not ClickHouse: sleeping on it spends the
        # batch's deadline for nothing, so it gets one check and goes back to the sweep.
        stale = pending.select { |_sub, ms| ms.to_i < stale_cutoff_ms }
        if stale.any?
          log_pending("usage buckets behind a stale watermark", stale)
          return :stale_watermark
        end

        if Time.current > deadline
          log_pending("usage buckets did not catch up before refresh", pending)
          return :bucket_wait_timeout
        end

        sleep BUCKET_WAIT_INTERVAL
      end
    end

    def bucket_caught_up?(subscription_id, watermark_ms)
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
      Rails.logger.warn("[wallets] #{reason} customer_id=#{customer_id} pending=#{pending.keys.inspect}")
    end
  end
end
