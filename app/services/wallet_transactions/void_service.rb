# frozen_string_literal: true

module WalletTransactions
  class VoidService < BaseService
    def initialize(wallet:, wallet_credit:, **transaction_params)
      @wallet = wallet
      @wallet_credit = wallet_credit
      @transaction_params = transaction_params

      super
    end

    def call
      return result if wallet_credit.credit_amount.zero?

      ActiveRecord::Base.transaction do
        wallet_transaction = CreateService.call!(
          **transaction_params,
          wallet:,
          wallet_credit:,
          transaction_type: :outbound,
          status: :settled,
          settled_at: Time.current,
          transaction_status: :voided
        ).wallet_transaction
        Wallets::Balance::DecreaseService.new(wallet:, wallet_transaction:).call
        result.wallet_transaction = wallet_transaction
      end

      result
    end

    private

    attr_reader :wallet, :wallet_credit, :transaction_params
  end
end
