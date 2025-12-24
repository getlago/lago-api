# frozen_string_literal: true

class AddAvailableInboundIndexToWalletTransactions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :wallet_transactions,
      [:wallet_id],
      where: "remaining_amount_cents > 0 AND transaction_type = 0 AND status = 1",
      name: "idx_wallet_transactions_available_inbound",
      algorithm: :concurrently
  end
end
