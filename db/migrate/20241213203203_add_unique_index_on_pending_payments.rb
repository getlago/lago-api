# frozen_string_literal: true

class AddUniqueIndexOnPendingPayments < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :payments,
      %i[payable_id payable_type],
      where: "status = 'pending'",
      unique: true,
      algorithm: :concurrently
  end
end
