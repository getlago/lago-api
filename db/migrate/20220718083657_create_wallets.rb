# frozen_string_literal: true

class CreateWallets < ActiveRecord::Migration[7.0]
  def change
    create_table :wallets, id: :uuid do |t|
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true

      t.integer :status, null: false
      t.string :currency, null: false

      t.string :name
      t.decimal :rate_amount, null: false, default: 0, precision: 5
      t.decimal :credits_balance, null: false, default: 0, precision: 5
      t.decimal :balance, null: false, default: 0, precision: 5
      t.decimal :consumed_credits, null: false, default: 0, precision: 5

      t.timestamp :expiration_date
      t.timestamp :last_balance_sync_at
      t.timestamp :last_consumed_credit_at
      t.timestamp :terminated_at

      t.timestamps
    end
  end
end
