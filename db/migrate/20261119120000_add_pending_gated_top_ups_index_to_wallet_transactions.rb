# frozen_string_literal: true

class AddPendingGatedTopUpsIndexToWalletTransactions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Read every hour by Clock::ExpirePendingTopUpsJob. Pending top-ups gated on a successful
  # payment are a tiny share of the table, which has no index on status.
  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:wallet_transactions, nil, name: :index_wallet_transactions_pending_gated_top_ups, valid: false)
      remove_index :wallet_transactions, name: :index_wallet_transactions_pending_gated_top_ups, algorithm: :concurrently
    end

    add_index :wallet_transactions,
      :created_at,
      where: "status = 0 AND transaction_type = 0 AND invoice_requires_successful_payment",
      name: :index_wallet_transactions_pending_gated_top_ups,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :wallet_transactions,
      name: :index_wallet_transactions_pending_gated_top_ups,
      algorithm: :concurrently,
      if_exists: true
  end
end
