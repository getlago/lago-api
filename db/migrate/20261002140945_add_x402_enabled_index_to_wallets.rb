# frozen_string_literal: true

class AddX402EnabledIndexToWallets < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:wallets, nil, name: :index_x402_enabled_wallets_on_customer_id, valid: false)
      remove_index :wallets, name: :index_x402_enabled_wallets_on_customer_id, algorithm: :concurrently
    end

    add_index :wallets,
      :customer_id,
      where: "x402_enabled",
      name: :index_x402_enabled_wallets_on_customer_id,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :wallets, name: :index_x402_enabled_wallets_on_customer_id, algorithm: :concurrently, if_exists: true
  end
end
