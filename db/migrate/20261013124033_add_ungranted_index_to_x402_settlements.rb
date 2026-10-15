# frozen_string_literal: true

class AddUngrantedIndexToX402Settlements < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    if index_exists?(:x402_settlements, nil, name: :index_x402_settlements_on_ungranted_id, valid: false)
      remove_index :x402_settlements, name: :index_x402_settlements_on_ungranted_id, algorithm: :concurrently
    end

    add_index :x402_settlements,
      :id,
      where: "kind = 'credit_purchase' AND status = 'settled' AND wallet_transaction_id IS NULL",
      name: :index_x402_settlements_on_ungranted_id,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :x402_settlements, name: :index_x402_settlements_on_ungranted_id, algorithm: :concurrently, if_exists: true
  end
end
