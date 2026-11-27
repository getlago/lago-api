# frozen_string_literal: true

module CatalogWallets
  module Ledger
    class SettleService < BaseService
      Result = BaseResult[:wallet_transaction]

      def initialize(wallet_transaction:)
        @wallet_transaction = wallet_transaction
        super
      end

      def call
        return result.forbidden_failure!(code: "wallet_transaction_not_inbound") unless wallet_transaction.inbound?

        with_ledger_lock(wallet) do
          wallet_transaction.lock!("FOR NO KEY UPDATE")
          next if wallet_transaction.settled?

          wallet_transaction.update!(
            status: :settled,
            settled_at: Time.current,
            failed_at: nil,
            remaining_credit_amount_cents: wallet_transaction.credit_amount_cents
          )
          move_balance(wallet, by: wallet_transaction.credit_amount_cents)
        end

        result.wallet_transaction = wallet_transaction
        result
      end

      private

      attr_reader :wallet_transaction

      def wallet
        @wallet ||= wallet_transaction.catalog_wallet
      end
    end
  end
end
