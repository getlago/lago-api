# frozen_string_literal: true

class IndexPendingFixedAdvanceAdjustments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    if index_exists?(:billing_operations, nil, name: :index_pending_fixed_advance_adjustments, valid: false)
      remove_index :billing_operations, name: :index_pending_fixed_advance_adjustments, algorithm: :concurrently
    end

    add_index :billing_operations, [:billing_at, :customer_id],
      name: :index_pending_fixed_advance_adjustments,
      where: "processed_at IS NULL AND cancelled_at IS NULL AND action_type = 'adjust_fixed_advance'",
      algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :billing_operations, name: :index_pending_fixed_advance_adjustments,
      algorithm: :concurrently, if_exists: true
  end
end
