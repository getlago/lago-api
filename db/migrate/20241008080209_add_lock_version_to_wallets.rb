# frozen_string_literal: true

class AddLockVersionToWallets < ActiveRecord::Migration[7.1]
  def change
    add_column :wallets, :lock_version, :integer, default: 0, null: false
  end
end
