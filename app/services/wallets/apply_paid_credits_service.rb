# frozen_string_literal: true

module Wallets
  class ApplyPaidCreditsService < BaseService
    def call(invoice)
      wallet_transaction = invoice.fees.find_by(fee_type: "credit")&.invoiceable

      return unless wallet_transaction
      return if wallet_transaction.status == "settled"

      WalletTransactions::SettleService.new(wallet_transaction:).call
      Wallets::Balance::IncreaseService
        .new(wallet: wallet_transaction.wallet, credits_amount: wallet_transaction.credit_amount).call
    end
  end
end
