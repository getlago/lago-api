# frozen_string_literal: true

module Wallets
  class FindApplicableOnFeesService < BaseService
    Result = BaseResult[:top_priority_wallet]

    def initialize(allocation_rules:, fee:, wallets: nil)
      @allocation_rules = allocation_rules
      @fee = fee
      @wallets = wallets
      super
    end

    def call
      # Check if fee has a specific wallet_id in grouped_by (highest priority)
      if (wallet_id = fee.grouped_by&.dig("wallet_id"))
        wallet = find_wallet_by_id(wallet_id)
        return result_with_wallet(wallet) if wallet
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

    attr_reader :allocation_rules, :fee, :wallets

    def find_wallet_by_id(wallet_id)
      return nil unless wallets

      wallets.find { |w| w.id == wallet_id }
    end

    def result_with_wallet(wallet)
      result.top_priority_wallet = wallet&.id
      result
    end

    def result_with(wallet_ids)
      result.top_priority_wallet = wallet_ids.first
      result
    end
  end
end
