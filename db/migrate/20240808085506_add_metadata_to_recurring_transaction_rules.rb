# frozen_string_literal: true

class AddMetadataToRecurringTransactionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :recurring_transaction_rules, :transaction_metadata, :jsonb, default: {}
  end
end
