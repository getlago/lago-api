# frozen_string_literal: true

class AddUniqueEventIndexOnFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees,
      %i[pay_in_advance_event_transaction_id charge_id charge_filter_id],
      unique: true,
      where: "created_at > '2025-01-21T00:00:00' AND pay_in_advance_event_transaction_id IS NOT NULL AND pay_in_advance = true",
      algorithm: :concurrently
  end
end
