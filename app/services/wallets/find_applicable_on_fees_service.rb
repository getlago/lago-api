# frozen_string_literal: true

module Wallets
  class FindApplicableOnFeesService < BaseService
    def initialize(allocation_rules:, fee:)
      @allocation_rules = allocation_rules
      @fee = fee
      super
    end

    def call
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

    attr_reader :allocation_rules, :fee

    def result_with(wallets)
      result.applicable_wallets = wallets.first
      result
    end
  end
end
