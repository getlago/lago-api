# frozen_string_literal: true

class AddX402EnabledToWallets < ActiveRecord::Migration[8.0]
  def change
    add_column :wallets, :x402_enabled, :boolean, null: false, default: false, if_not_exists: true
  end
end
