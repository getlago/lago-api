# frozen_string_literal: true

module CatalogWallets
  module Ledger
    class BaseService < ::BaseService
      private

      # The lock is per customer, not per contract: one invoice can draw on the wallets of several contracts.
      def with_ledger_lock(wallet)
        Customers::LockService.call(customer: wallet.customer, scope: :catalog_wallet) do
          # Unlike FOR UPDATE, it lets rows that reference the wallet be inserted meanwhile.
          wallet.lock!("FOR NO KEY UPDATE")

          yield
        end
      end

      def move_balance(wallet, by:)
        wallet.balance_cents += by
        # Not validated: a balance must still move on a deleted wallet whose code is in use again.
        wallet.save!(validate: false)

        after_commit { CatalogWallets::ThresholdTopUpService.call(wallet:) }
      end
    end
  end
end
