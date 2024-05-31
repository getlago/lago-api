# frozen_string_literal: true

module WalletTransactions
  class VoidService < BaseService
    def initialize(wallet:, credits:, from_source: :manual)
      @wallet = wallet
      @credits = credits
      @from_source = from_source

      super
    end

    def call
      return if credits_amount.zero?

      ActiveRecord::Base.transaction do
        wallet_transaction = wallet.wallet_transactions.create!(
          transaction_type: :outbound,
          amount: wallet.rate_amount * credits_amount,
          credit_amount: credits_amount,
          status: :settled,
          settled_at: Time.current,
          source: from_source,
          transaction_status: :voided
        )
        Wallets::Balance::DecreaseService.new(wallet:, credits_amount:).call
        result.wallet_transaction = wallet_transaction
      end

      result
    end

    private

    attr_reader :wallet, :credits, :from_source

    def credits_amount
      @credits_amount ||= BigDecimal(credits)
    end
  end
end
