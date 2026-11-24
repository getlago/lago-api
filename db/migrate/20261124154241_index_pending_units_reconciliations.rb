# frozen_string_literal: true

class IndexPendingUnitsReconciliations < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:billing_operations, nil, name: :index_pending_units_reconciliations, valid: false)
      remove_index :billing_operations, name: :index_pending_units_reconciliations, algorithm: :concurrently
    end

    add_index :billing_operations, [:billing_at, :customer_id],
      name: :index_pending_units_reconciliations,
      where: "processed_at IS NULL AND cancelled_at IS NULL AND action_type = 'reconcile_units'",
      algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :billing_operations, name: :index_pending_units_reconciliations,
      algorithm: :concurrently, if_exists: true
  end
end
