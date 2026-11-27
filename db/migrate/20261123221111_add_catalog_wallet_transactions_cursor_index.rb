# frozen_string_literal: true

class AddCatalogWalletTransactionsCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:catalog_wallet_transactions, nil, name: :index_catalog_wallet_transactions_by_cursor, valid: false)
      remove_index :catalog_wallet_transactions, name: :index_catalog_wallet_transactions_by_cursor, algorithm: :concurrently
    end

    add_index :catalog_wallet_transactions,
      [:catalog_wallet_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      name: :index_catalog_wallet_transactions_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :catalog_wallet_transactions, name: :index_catalog_wallet_transactions_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
