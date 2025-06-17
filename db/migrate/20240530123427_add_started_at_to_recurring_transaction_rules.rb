# frozen_string_literal: true

class AddStartedAtToRecurringTransactionRules < ActiveRecord::Migration[7.0]
  def change
    add_column :recurring_transaction_rules, :started_at, :datetime
    safety_assured do
      add_index :recurring_transaction_rules, :started_at
    end
  end
end
