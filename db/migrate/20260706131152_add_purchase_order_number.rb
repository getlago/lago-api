# frozen_string_literal: true

class AddPurchaseOrderNumber < ActiveRecord::Migration[8.0]
  def change
    add_column :recurring_transaction_rules, :purchase_order_number, :string
    add_column :subscriptions, :purchase_order_number, :string
    add_column :wallet_transactions, :purchase_order_number, :string
    add_column :wallets, :purchase_order_number, :string
  end
end
