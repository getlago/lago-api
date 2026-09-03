# frozen_string_literal: true

module Wallets
  # Event-driven wallet refresh, triggered by the realtime usage pipeline
  # (wallet_refresh_triggers Kafka topic) instead of the awaiting-refresh
  # flag + clock sweep.
  #
  # Mirrors Customers::RefreshWalletJob semantics: same tax-error guard, and
  # the refresh always covers every wallet of the customer through
  # Customers::RefreshWalletsService (the allocation cascade makes wallets
  # interdependent). wallet_codes carries the targeting intent from events
  # (properties.target_wallet_code): it forces the refresh like the job's
  # wallet_ids argument does, it does not narrow it.
  #
  # Serialization is guaranteed upstream: triggers are keyed by
  # (organization_id, customer_id) on the Kafka topic, so one customer's
  # refreshes are always consumed sequentially from a single partition.
  class RealtimeRefreshService < BaseService
    Result = BaseResult[:wallets]

    # The Kafka trigger and the ClickHouse bucket upsert are two sinks of
    # the same RisingWave epoch with no cross-sink ordering guarantee: a fast
    # consumer can refresh BEFORE the bucket row landed and compute the
    # previous epoch's usage. expected_ingested_at maps subscription_id =>
    # the trigger's last_ingested_at watermark; the refresh waits (bounded)
    # until the buckets catch up to it.
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
      return result if customer.nil?
      return result unless customer.wallets.active.exists?
      return result if customer.error_details.tax_error.exists?

      wait_for_buckets

      if wallet_codes.present? && customer.wallets.active.where(code: wallet_codes).none?
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

    def wait_for_buckets
      pending = expected_ingested_at
        .reject { |_sub, ms| ms.to_i < ((Time.current - STALE_WATERMARK_CUTOFF).to_f * 1000).to_i }
        .dup
      return if pending.empty?

      deadline = Time.current + BUCKET_WAIT_TIMEOUT

      loop do
        pending.delete_if do |subscription_id, watermark_ms|
          # Millisecond-granularity comparison on integers: float Time
          # conversion is off by up to a microsecond and can never match.
          # No FINAL needed: any row version at the watermark proves the
          # epoch's upsert landed. uncached: Karafka consumes inside the
          # Rails executor, which turns on the AR query cache — without it,
          # a poll that runs before the bucket lands is replayed from cache
          # every iteration and the wait can only time out.
          #
          # organization_id is not redundant with subscription_id: it is the
          # first column of the table's ORDER BY, and without it this poll
          # cannot use the primary key at all. Measured on a 172M-row table:
          # 3.65M rows scanned without it, 8.2k with — and this runs every
          # BUCKET_WAIT_INTERVAL for as long as the wait lasts.
          Clickhouse::UsageBucket.uncached do
            Clickhouse::UsageBucket
              .where(organization_id:, subscription_id:)
              .where("toUnixTimestamp64Milli(last_ingested_at) >= ?", watermark_ms.to_i)
              .exists?
          end
        end
        break if pending.empty?

        if Time.current > deadline
          Rails.logger.warn(
            "[wallets] usage buckets did not catch up before refresh " \
            "customer_id=#{customer_id} pending=#{pending.keys.inspect}"
          )
          break
        end

        sleep BUCKET_WAIT_INTERVAL
      end
    end
  end
end
