class AddExpirationAndTerminationToRecurringTransactionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :recurring_transaction_rules, :expiration_at, :datetime
    add_column :recurring_transaction_rules, :terminated_at, :datetime
  end
end
