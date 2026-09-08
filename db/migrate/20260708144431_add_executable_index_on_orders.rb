# frozen_string_literal: true

class AddExecutableIndexOnOrders < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :orders,
      :execute_at,
      where: "status = 'created' AND execute_at IS NOT NULL",
      algorithm: :concurrently,
      if_not_exists: true
  end
end
