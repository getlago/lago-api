# frozen_string_literal: true

module Wallets
  # wallet_codes carries the events' targeting intent (properties.target_wallet_code): it forces
  # the refresh, it does not narrow it — the allocation cascade makes wallets interdependent.
  class RealtimeRefreshService < BaseService
    Result = BaseResult[:wallets]

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
      return result if customer.nil?
      return result unless customer.wallets.active.exists?

      # Refreshing on buckets that have not caught up writes a stale balance and clears
      # awaiting_wallet_refresh, the flag the sweep selects on: nothing would correct it after.
      return result unless wait_for_buckets

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
      stale_cutoff_ms = ((Time.current - STALE_WATERMARK_CUTOFF).to_f * 1000).to_i
      pending = expected_ingested_at.reject { |_sub, ms| ms.to_i < stale_cutoff_ms }
      return true if pending.empty?

      deadline = Time.current + BUCKET_WAIT_TIMEOUT

      loop do
        pending.delete_if do |subscription_id, watermark_ms|
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
        return true if pending.empty?

        if Time.current > deadline
          Rails.logger.warn(
            "[wallets] usage buckets did not catch up before refresh " \
            "customer_id=#{customer_id} pending=#{pending.keys.inspect}"
          )
          return false
        end

        sleep BUCKET_WAIT_INTERVAL
      end
    end
  end
end
