# frozen_string_literal: true

module WalletTransactions
  class MarkAsFailedService < BaseService
    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      super
    end

    activity_loggable(
      action: "wallet_transaction.updated",
      record: -> { wallet_transaction }
    )

    def call
      return result unless wallet_transaction
      return result if wallet_transaction.status == "failed"
      # note: if a wallet transaction is settled, but they mark payment as failed, they need to void credits manually
      return result if wallet_transaction.status == "settled"

      wallet_transaction.mark_as_failed!
      SendWebhookJob.perform_later("wallet_transaction.updated", wallet_transaction)
      result.wallet_transaction = wallet_transaction
      result
    end

    private

    attr_reader :wallet_transaction
  end
end
