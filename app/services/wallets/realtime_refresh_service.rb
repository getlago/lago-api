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

    def initialize(organization_id:, customer_id:, wallet_codes: [])
      @organization_id = organization_id
      @customer_id = customer_id
      @wallet_codes = wallet_codes

      super
    end

    def call
      result.wallets = []

      customer = Customer.find_by(id: customer_id, organization_id:)
      return result if customer.nil?
      return result unless customer.wallets.active.exists?
      return result if customer.error_details.tax_error.exists?

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

    attr_reader :organization_id, :customer_id, :wallet_codes
  end
end
