# frozen_string_literal: true

class AddUnpaidIndexToX402Settlements < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:x402_settlements, nil, name: :index_x402_settlements_on_unpaid_id, valid: false)
      remove_index :x402_settlements, name: :index_x402_settlements_on_unpaid_id, algorithm: :concurrently
    end

    add_index :x402_settlements,
      :id,
      where: "kind = 'invoice_payment' AND status = 'settled' AND payment_id IS NULL AND error_reason IS DISTINCT FROM 'payment_not_recorded'",
      name: :index_x402_settlements_on_unpaid_id,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :x402_settlements, name: :index_x402_settlements_on_unpaid_id, algorithm: :concurrently, if_exists: true
  end
end
