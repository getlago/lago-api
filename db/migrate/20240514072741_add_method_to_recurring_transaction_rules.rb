# frozen_string_literal: true

class AddMethodToRecurringTransactionRules < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :recurring_transaction_rules, :rule_type, :trigger
    end
    add_column :recurring_transaction_rules, :method, :integer, null: false, default: 0
  end
end
