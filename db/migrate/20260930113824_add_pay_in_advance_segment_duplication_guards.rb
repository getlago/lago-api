# frozen_string_literal: true

class AddPayInAdvanceSegmentDuplicationGuards < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:fees, nil, name: :idx_pay_in_advance_duplication_guard_contract_rate_card, valid: false)
      remove_index :fees, name: :idx_pay_in_advance_duplication_guard_contract_rate_card, algorithm: :concurrently
    end

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :contract_rate_card_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_contract_rate_card,
      where: "deleted_at IS NULL AND charge_id IS NULL AND contract_rate_card_id IS NOT NULL AND product_filter_id IS NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false AND original_fee_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true

    if index_exists?(:fees, nil, name: :idx_pay_in_advance_duplication_guard_contract_rate_card_filter, valid: false)
      remove_index :fees, name: :idx_pay_in_advance_duplication_guard_contract_rate_card_filter, algorithm: :concurrently
    end

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :contract_rate_card_id, :product_filter_id],
      unique: true,
      name: :idx_pay_in_advance_duplication_guard_contract_rate_card_filter,
      where: "deleted_at IS NULL AND charge_id IS NULL AND contract_rate_card_id IS NOT NULL AND product_filter_id IS NOT NULL AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true AND duplicated_in_advance = false AND original_fee_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :fees, name: :idx_pay_in_advance_duplication_guard_contract_rate_card_filter, algorithm: :concurrently, if_exists: true
    remove_index :fees, name: :idx_pay_in_advance_duplication_guard_contract_rate_card, algorithm: :concurrently, if_exists: true
  end
end
