# frozen_string_literal: true

class AddIndexOnFeesPayInAdvanceEventTransactionId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees, :pay_in_advance_event_transaction_id,
      where: 'deleted_at IS NULL',
      algorithm: :concurrently,
      if_not_exists: true
  end
end
