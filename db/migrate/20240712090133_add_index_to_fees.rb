# frozen_string_literal: true

class AddIndexToFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees, [:charge_id, :invoice_id],
      where: 'deleted_at IS NULL',
      algorithm: :concurrently,
      if_not_exists: true
  end
end
