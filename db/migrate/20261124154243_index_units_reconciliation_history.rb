# frozen_string_literal: true

class IndexUnitsReconciliationHistory < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:billing_operations, nil, name: :index_units_reconciliation_history, valid: false)
      remove_index :billing_operations, name: :index_units_reconciliation_history, algorithm: :concurrently
    end

    add_index :billing_operations, [:contract_rate_card_id, :billing_at], unique: true,
      name: :index_units_reconciliation_history, where: "reason = 'contract_units_change'",
      algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :billing_operations, name: :index_units_reconciliation_history,
      algorithm: :concurrently, if_exists: true
  end
end
