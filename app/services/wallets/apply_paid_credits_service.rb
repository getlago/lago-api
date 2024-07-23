# frozen_string_literal: true

module Wallets
  class ApplyPaidCreditsService < BaseService
    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      super
    end

    def call
      return result unless wallet_transaction
      return result if wallet_transaction.status == 'settled'

      WalletTransactions::SettleService.new(wallet_transaction:).call
      Wallets::Balance::IncreaseService
        .new(wallet: wallet_transaction.wallet, credits_amount: wallet_transaction.credit_amount).call

      result.wallet_transaction = wallet_transaction
      result
    end

    private

    attr_reader :wallet_transaction
  end
end
