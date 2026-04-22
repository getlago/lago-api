# frozen_string_literal: true

class UpdatePayInAdvanceDuplicationGuardIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :fees, name: :idx_pay_in_advance_duplication_guard_charge, if_exists: true
    remove_index :fees, name: :idx_pay_in_advance_duplication_guard_charge_filter, if_exists: true

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :charge_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_charge,
      where: "deleted_at IS NULL AND charge_filter_id IS NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false AND original_fee_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :charge_id, :charge_filter_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_charge_filter,
      where: "deleted_at IS NULL AND charge_filter_id IS NOT NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false AND original_fee_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :fees, name: :idx_pay_in_advance_duplication_guard_charge, if_exists: true
    remove_index :fees, name: :idx_pay_in_advance_duplication_guard_charge_filter, if_exists: true

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :charge_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_charge,
      where: "deleted_at IS NULL AND charge_filter_id IS NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :charge_id, :charge_filter_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_charge_filter,
      where: "deleted_at IS NULL AND charge_filter_id IS NOT NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
