# frozen_string_literal: true

class AddTargetOngoingBalanceToRecurringTransactionRules < ActiveRecord::Migration[7.0]
  def change
    add_column :recurring_transaction_rules,
      :target_ongoing_balance,
      :decimal,
      precision: 30,
      scale: 5
  end
end
