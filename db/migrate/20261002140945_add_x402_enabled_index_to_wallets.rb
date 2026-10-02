# frozen_string_literal: true

class AddX402EnabledIndexToWallets < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:wallets, nil, name: :index_wallets_on_x402_enabled, valid: false)
      remove_index :wallets, name: :index_wallets_on_x402_enabled, algorithm: :concurrently
    end

    add_index :wallets,
      :x402_enabled,
      where: "x402_enabled",
      name: :index_wallets_on_x402_enabled,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :wallets, name: :index_wallets_on_x402_enabled, algorithm: :concurrently, if_exists: true
  end
end
