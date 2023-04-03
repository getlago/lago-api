# frozen_string_literal: true

module Wallets
  module Balance
    class IncreaseService < BaseService
      def initialize(wallet:, credits_amount:)
        super(nil)

        @wallet = wallet
        @credits_amount = credits_amount
      end

      def call
        currency = wallet.balance.currency
        amount_cents = wallet.rate_amount * credits_amount * currency.subunit_to_unit

        wallet.update!(
          balance_cents: wallet.balance_cents + amount_cents,
          credits_balance: wallet.credits_balance + credits_amount,
          last_balance_sync_at: Time.current,
        )

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :credits_amount
    end
  end
end
