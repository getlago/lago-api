# frozen_string_literal: true

class AddPendingBillingOperationsCardClockIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = :index_pending_billing_operations_on_card_and_date

  def up
    if index_exists?(:billing_operations, nil, name: INDEX_NAME, valid: false)
      remove_index :billing_operations, name: INDEX_NAME, algorithm: :concurrently
    end

    add_index :billing_operations, [:contract_rate_card_id, :billing_at],
      name: INDEX_NAME,
      where: "processed_at IS NULL AND cancelled_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :billing_operations, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
