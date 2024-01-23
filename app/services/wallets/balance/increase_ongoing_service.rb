# frozen_string_literal: true

module Wallets
  module Balance
    class IncreaseOngoingService < BaseService
      def initialize(wallet:, credits_amount:)
        super(nil)

        @wallet = wallet
        @credits_amount = credits_amount
      end

      def call
        currency = wallet.ongoing_balance.currency
        amount_cents = wallet.rate_amount * credits_amount * currency.subunit_to_unit

        update_params = {
          ongoing_balance_cents: wallet.ongoing_balance_cents + amount_cents,
          credits_ongoing_balance: wallet.credits_ongoing_balance + credits_amount,
        }

        wallet.update!(update_params)

        result.wallet = wallet
        result
      end

      private

      attr_reader :wallet, :credits_amount
    end
  end
end
