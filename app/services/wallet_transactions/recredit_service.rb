# frozen_string_literal: true

module WalletTransactions
  class RecreditService < BaseService
    def initialize(wallet_transaction:)
      @wallet_transaction = wallet_transaction
      @wallet = wallet_transaction.wallet
      @customer = @wallet.customer

      super
    end

    def call
      result.wallet_transaction = wallet_transaction

      return result.not_allowed_failure!(code: "wallet_not_active") unless wallet.active?

      transaction_result = WalletTransactions::CreateFromParamsService.call(
        organization: customer.organization,
        params: {
          wallet_id: wallet.id,
          granted_credits: wallet_transaction.credit_amount.to_s,
          reset_consumed_credits: true
        }
      )

      return transaction_result unless transaction_result.success?

      result
    end

    private

    attr_reader :wallet_transaction, :wallet, :customer
  end
end
