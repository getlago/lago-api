# frozen_string_literal: true

class AddWalletConfig < ActiveRecord::Migration[7.1]
  def change
    add_column :wallets, :config, :jsonb, default: {}, null: false
    add_column :wallet_transactions, :config, :jsonb, default: {}, null: false
    add_column :recurring_transaction_rules, :config, :jsonb, default: {}, null: false
  end
end
