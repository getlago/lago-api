# frozen_string_literal: true

class AddLockVersionToWalletTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :wallet_transactions, :lock_version, :integer, default: 0, null: false
  end
end
