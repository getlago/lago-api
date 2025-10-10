# frozen_string_literal: true

module Wallets
  class FindApplicableOnFeesService < BaseService
    def initialize(wallet_allocation:, fee:, first_match: false)
      @wallet_allocation = wallet_allocation
      @fee = fee
      @first_match = first_match
      super
    end

    def call
      bm_id = fee.charge&.billable_metric_id

      bm_wallets = wallet_allocation[:bm_map][bm_id]
      return result_with(bm_wallets) if bm_wallets&.any?

      type_wallets = wallet_allocation[:type_map][fee.fee_type]
      return result_with(type_wallets) if type_wallets&.any?

      unrestricted_wallets = wallet_allocation[:unrestricted]
      return result_with(unrestricted_wallets) if unrestricted_wallets&.any?

      result_with([])
    end

    private

    attr_reader :wallet_allocation, :fee, :first_match

    def result_with(wallets)
      result.applicable_wallets = first_match ? wallets.first : wallets
      result
    end
  end
end
