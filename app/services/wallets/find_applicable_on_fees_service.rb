# frozen_string_literal: true

module Wallets
  class FindApplicableOnFeesService < BaseService
    Result = BaseResult[:top_priority_wallet]

    def initialize(allocation_rules:, fee:, customer_id: nil, fee_targeting_wallets_enabled: nil)
      @allocation_rules = allocation_rules
      @fee = fee
      @customer_id = customer_id
      @fee_targeting_wallets_enabled = fee_targeting_wallets_enabled
      super
    end

    def call
      # Priority 1: Check for target_wallet_code in fee.grouped_by
      if fee_targeting_wallets_enabled && fee.charge&.accepts_target_wallet
        target_wallet_code = fee.grouped_by&.dig("target_wallet_code")
        if target_wallet_code.present?
          targeted_wallet = find_wallet_by_code(target_wallet_code)
          return result_with([targeted_wallet.id]) if targeted_wallet
        end
      end

      bm_id = fee.charge&.billable_metric_id

      bm_wallets = allocation_rules[:bm_map][bm_id]
      return result_with(bm_wallets) if bm_wallets&.any?

      type_wallets = allocation_rules[:type_map][fee.fee_type]
      return result_with(type_wallets) if type_wallets&.any?

      unrestricted_wallets = allocation_rules[:unrestricted]
      return result_with(unrestricted_wallets) if unrestricted_wallets&.any?

      result_with([])
    end

    private

    attr_reader :allocation_rules, :fee, :fee_targeting_wallets_enabled

    def find_wallet_by_code(code)
      wallet_customer_id = @customer_id || fee.subscription&.customer_id || fee.invoice&.customer_id
      return nil unless wallet_customer_id

      Wallet.active.find_by(organization_id: fee.organization_id, customer_id: wallet_customer_id, code:)
    end

    def result_with(wallets)
      result.top_priority_wallet = wallets.first
      result
    end
  end
end
