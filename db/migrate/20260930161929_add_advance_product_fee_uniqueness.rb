# frozen_string_literal: true

class AddAdvanceProductFeeUniqueness < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index that `if_not_exists` would keep.
    if index_exists?(:fees, nil, name: :idx_pay_in_advance_product_card_event, valid: false)
      remove_index :fees, name: :idx_pay_in_advance_product_card_event, algorithm: :concurrently
    end

    add_index :fees,
      [:pay_in_advance_event_transaction_id, :contract_rate_card_id],
      unique: true,
      name: :idx_pay_in_advance_product_card_event,
      where: "deleted_at IS NULL AND charge_id IS NULL AND contract_rate_card_id IS NOT NULL " \
        "AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true " \
        "AND duplicated_in_advance = false AND original_fee_id IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :fees, name: :idx_pay_in_advance_product_card_event, algorithm: :concurrently, if_exists: true
  end
end
