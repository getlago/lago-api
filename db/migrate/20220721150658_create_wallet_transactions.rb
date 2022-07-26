# frozen_string_literal: true

class CreateWalletTransactions < ActiveRecord::Migration[7.0]
  def change
    create_table :wallet_transactions, id: :uuid do |t|
      t.references :wallet, type: :uuid, null: false, foreign_key: true, index: true

      t.integer :transaction_type, null: false
      t.integer :status, null: false

      t.decimal :amount, null: false, default: 0, precision: 5
      t.decimal :credit_amount, null: false, default: 0, precision: 5

      t.timestamp :settled_at

      t.timestamps
    end
  end
end
