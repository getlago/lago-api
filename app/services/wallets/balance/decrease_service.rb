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
        amount = wallet.rate_amount * credits_amount

        wallet.update!(
          balance: wallet.balance - amount,
          credits_balance: wallet.credits_balance - credits_amount,
          last_balance_sync_at: Time.zone.now,
          consumed_credits: wallet.consumed_credits + credits_amount,
          consumed_amount: wallet.consumed_amount + amount,
          last_consumed_credit_at: Time.current
        )

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :credits_amount
    end
  end
end
