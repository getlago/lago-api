# frozen_string_literal: true

class CreateRecurringTransactionRules < ActiveRecord::Migration[7.0]
  def change
    create_table :recurring_transaction_rules, id: :uuid do |t|
      t.references :wallet, type: :uuid, null: false, foreign_key: true, index: true

      t.integer :rule_type, default: 0, null: false
      t.decimal :paid_credits, null: false, default: 0, precision: 30, scale: 5
      t.decimal :granted_credits, null: false, default: 0, precision: 30, scale: 5
      t.decimal :threshold_credits, null: true, default: 0, precision: 30, scale: 5
      t.integer :interval, default: 0, null: true

      t.timestamps
    end

    add_column :wallet_transactions, :source, :integer, default: 0, null: false
  end
end
