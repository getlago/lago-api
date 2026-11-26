# frozen_string_literal: true

module CatalogWallets
  module Ledger
    class FailService < BaseService
      Result = BaseResult[:wallet_transaction]

      def initialize(wallet_transaction:)
        @wallet_transaction = wallet_transaction
        super
      end

      def call
        with_ledger_lock(wallet_transaction.catalog_wallet) do
          wallet_transaction.lock!("FOR NO KEY UPDATE")
          next unless wallet_transaction.pending?

          wallet_transaction.update!(status: :failed, failed_at: Time.current)
        end

        result.wallet_transaction = wallet_transaction
        result
      end

      private

      attr_reader :wallet_transaction
    end
  end
end
