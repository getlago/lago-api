# frozen_string_literal: true

class RemoveCatalogWalletTransactionsCatalogWalletIdIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # index_catalog_wallet_transactions_by_cursor leads with catalog_wallet_id and serves every lookup this one did.
  def up
    remove_index :catalog_wallet_transactions,
      name: :index_catalog_wallet_transactions_on_catalog_wallet_id,
      algorithm: :concurrently,
      if_exists: true
  end

  def down
    if index_exists?(:catalog_wallet_transactions, nil, name: :index_catalog_wallet_transactions_on_catalog_wallet_id, valid: false)
      remove_index :catalog_wallet_transactions, name: :index_catalog_wallet_transactions_on_catalog_wallet_id, algorithm: :concurrently
    end

    add_index :catalog_wallet_transactions, :catalog_wallet_id,
      name: :index_catalog_wallet_transactions_on_catalog_wallet_id,
      algorithm: :concurrently,
      if_not_exists: true
  end
end
