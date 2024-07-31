# frozen_string_literal: true

class AddIndexOnPaymentsPayableIdAndPayableType < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :payments, [:payable_type, :payable_id], algorithm: :concurrently, if_not_exists: true
  end
end
