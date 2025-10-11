# frozen_string_literal: true

# app/services/wallets/build_allocation_rules_service.rb
module Wallets
  class FindApplicableOnFeesService < BaseService
    def initialize(wallet_allocation:, fee:, first_match: false)
      @wallet_allocation = wallet_allocation
      @fee = fee
      @first_match = first_match
      super
    end

    def call
      applicable_wallets = []
      bm_id = fee.respond_to?(:charge) ? fee.charge&.billable_metric_id : nil

      if wallet_allocation[:bm_map][bm_id].present?
        applicable_wallets.concat(wallet_allocation[:bm_map][bm_id])
      end

      if wallet_allocation[:type_map][fee.fee_type].present? && applicable_wallets.empty?
        applicable_wallets.concat(wallet_allocation[:type_map][fee.fee_type])
      end

      if wallet_allocation[:unrestricted].present? && applicable_wallets.empty?
        applicable_wallets.concat(wallet_allocation[:unrestricted])
      end

      result.applicable_wallets = first_match ? applicable_wallets.first : applicable_wallets
      result
    end

    private

    attr_reader :wallet_allocation, :fee, :first_match
  end
end
