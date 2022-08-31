# frozen_string_literal: true

module WalletTransactions
  class SettleService < BaseService
    def initialize(wallet_transaction:)
      super(nil)

      @wallet_transaction = wallet_transaction
    end

    def call
      wallet_transaction.update!(status: :settled, settled_at: Time.current)

      result.wallet_transaction = wallet_transaction
      result
    end

    private

    attr_reader :wallet_transaction
  end
end
