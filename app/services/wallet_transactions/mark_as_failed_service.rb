# frozen_string_literal: true

module WalletTransactions
  class MarkAsFailedService < BaseService
    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      super
    end

    def call
      return result unless wallet_transaction
      return result if wallet_transaction.status == "failed"

      ActiveRecord::Base.transaction do
        if wallet_transaction.settled? && wallet_transaction.inbound?
          Wallets::Balance::DecreaseService
            .new(wallet: wallet_transaction.wallet, wallet_transaction: wallet_transaction).call
        end
        wallet_transaction.mark_as_failed!
      end
      SendWebhookJob.perform_later("wallet_transaction.updated", wallet_transaction)
      result.wallet_transaction = wallet_transaction
      result
    end

    private

    attr_reader :wallet_transaction
  end
end
