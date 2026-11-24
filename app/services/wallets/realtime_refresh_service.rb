# frozen_string_literal: true

module Wallets
  # wallet_codes carries the events' targeting intent (properties.target_wallet_code): it forces
  # the refresh, it does not narrow it — the allocation cascade makes wallets interdependent.
  class RealtimeRefreshService < BaseService
    Result = BaseResult[:wallets, :reason]

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

      RealtimeUsage::BucketWatermark.consistent_reads { refresh(customer) }
    end

    private

    attr_reader :organization_id, :customer_id, :wallet_codes, :expected_ingested_at

    def refresh(customer)
      # Refreshing on buckets that have not caught up writes a stale balance and clears
      # awaiting_wallet_refresh, the flag the sweep selects on: nothing would correct it after.
      wait_reason = RealtimeUsage::BucketWatermark.wait(organization_id:, pending: expected_ingested_at, lane: :wallet_refresh)
      return skipped(wait_reason) if wait_reason

      if wallet_codes.present? && customer.wallets.active.where(code: wallet_codes).none?
        Rails.logger.warn(
          "[wallets] realtime refresh targeted unknown wallet codes " \
          "customer_id=#{customer.id} codes=#{wallet_codes.inspect}"
        )
      end

      started_at = Time.current
      refresh_result = Customers::RefreshWalletsService.call(customer:)
      Yabeda.realtime_usage.wallet_refresh_duration.measure({}, Time.current - started_at)
      return refresh_result unless refresh_result.success?

      result.wallets = refresh_result.wallets
      result
    end

    def skipped(reason)
      result.reason = reason
      result
    end
  end
end
