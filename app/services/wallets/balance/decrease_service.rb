# frozen_string_literal: true

module Wallets
  module Balance
    class DecreaseService < BaseService
      def initialize(wallet:, credits_amount:)
        super(nil)

        @wallet = wallet
        @credits_amount = credits_amount
      end

      def call
        amount = BigDecimal(wallet.rate_amount) * credits_amount

        wallet.update(
          balance: BigDecimal(wallet.balance) - amount,
          credits_balance: BigDecimal(wallet.credits_balance) - credits_amount,
          last_balance_sync_at: Time.zone.now,
        )
      end

      private

      attr_reader :wallet, :credits_amount
    end
  end
end
