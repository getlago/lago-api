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

    # The Kafka trigger and the Postgres projection upsert are two sinks of
    # the same RisingWave epoch with no cross-sink ordering guarantee: a fast
    # consumer can refresh BEFORE the projection row landed and compute the
    # previous epoch's usage. expected_ingested_at maps subscription_id =>
    # the trigger's last_ingested_at watermark; the refresh waits (bounded)
    # until projections catch up to it.
    PROJECTION_WAIT_TIMEOUT = 5.seconds
    PROJECTION_WAIT_INTERVAL = 0.1

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

      wait_for_projections

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

    def wait_for_projections
      pending = expected_ingested_at.dup
      return if pending.empty?

      deadline = Time.current + PROJECTION_WAIT_TIMEOUT

      loop do
        pending.delete_if do |subscription_id, watermark_ms|
          # Millisecond-granularity comparison on integers: float Time
          # conversion is off by up to a microsecond and can never match.
          # uncached: Karafka consumes inside the Rails executor, which turns
          # on the AR query cache — without it, a poll that runs before the
          # projection lands is replayed from cache every iteration and the
          # wait can only time out.
          UsageRealtimeProjection.uncached do
            UsageRealtimeProjection
              .where(subscription_id:)
              .where("(EXTRACT(EPOCH FROM last_ingested_at) * 1000)::bigint >= ?", watermark_ms.to_i)
              .exists?
          end
        end
        break if pending.empty?

        if Time.current > deadline
          Rails.logger.warn(
            "[wallets] projections did not catch up before refresh " \
            "customer_id=#{customer_id} pending=#{pending.keys.inspect}"
          )
          break
        end

        sleep PROJECTION_WAIT_INTERVAL
      end
    end
  end
end
