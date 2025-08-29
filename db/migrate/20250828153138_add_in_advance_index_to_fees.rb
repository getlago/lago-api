# frozen_string_literal: true

class AddInAdvanceIndexToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :fees,
      [:pay_in_advance_event_transaction_id, :charge_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_charge,
      where: "charge_filter_id IS NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
